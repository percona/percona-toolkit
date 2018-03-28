#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;
use Time::HiRes qw(sleep);

$ENV{PTTEST_FAKE_TS} = 1;
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-online-schema-change";
require VersionParser;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp         = new DSNParser(opts=>$dsn_opts);
my $sb         = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}

my $q      = new Quoter();
my $tp     = new TableParser(Quoter => $q);
my @args   = qw(--set-vars innodb_lock_wait_timeout=3);
my $output = "";
my $dsn    = "h=127.1,P=12345,u=msandbox,p=msandbox";
my $exit   = 0;
my $sample = "t/pt-online-schema-change/samples";
my $rows;

# #############################################################################
# A helper sub to do the heavy lifting for us.
# #############################################################################

sub test_alter_table {
   my (%args) = @_;
   return if $args{skip};

   my @required_args = qw(name table test_type cmds);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($name, $table, $test_type, $cmds) = @args{@required_args};

   my ($db, $tbl) = $q->split_unquote($table);
   my $table_name = $tbl;
   my $pk_col     = $args{pk_col} || 'id';
   my $delete_triggers = $args{delete_triggers} || '';

   if ( my $file = $args{file} ) {
      $sb->load_file('master', "$sample/$file");
      $master_dbh->do("USE `$db`");
      $slave_dbh->do("USE `$db`");
   }

   my $ddl        = $tp->get_create_table($master_dbh, $db, $tbl);
   my $tbl_struct = $tp->parse($ddl);

   my $cols = '*';
   if ( $test_type =~ m/(?:add|drop)_col/  && !grep { $_ eq '--dry-run' } @$cmds ) {
      # Don't select the column being dropped.
      my $col = $args{drop_col} || $args{new_col};
      die "I need a drop_col argument" unless $col;
      $cols = join(', ', grep { $_ ne $col } @{$tbl_struct->{cols}});
   }
   my $orig_rows = $master_dbh->selectall_arrayref(
      "SELECT $cols FROM $table ORDER BY `$pk_col`");

   my $orig_tbls = $master_dbh->selectall_arrayref(
      "SHOW TABLES FROM `$db`");

   my $orig_max_id = $master_dbh->selectall_arrayref(
      "SELECT MAX(`$pk_col`) FROM `$db`.`$tbl`");

   my $triggers_sql = "SELECT TRIGGER_SCHEMA, TRIGGER_NAME, DEFINER, ACTION_STATEMENT, SQL_MODE, "
                    . "       CHARACTER_SET_CLIENT, COLLATION_CONNECTION, EVENT_MANIPULATION, ACTION_TIMING "
                    . "  FROM INFORMATION_SCHEMA.TRIGGERS "
                    . " WHERE TRIGGER_SCHEMA = '$db' " 
                    .  "  AND EVENT_OBJECT_TABLE = '$tbl'";
   my $orig_triggers = $master_dbh->selectall_arrayref($triggers_sql);

   my ($orig_auto_inc) = $ddl =~ m/\s+AUTO_INCREMENT=(\d+)\s+/;

   my $fk_method = $args{check_fks};
   my @orig_fks;
   if ( $fk_method ) {
      foreach my $tbl ( @$orig_tbls ) {
         my $fks = $tp->get_fks(
            $tp->get_create_table($master_dbh, $db, $tbl->[0]));
         push @orig_fks, $fks;
      }
   }

   # If --no-drop-new-table is given, then the new, altered table
   # should still exist, but not yet, so add it to the list so
   # is_deeply() against $new_tbls passes.  This only works for
   # single-table tests.
   my $new_tbl = $args{new_table} || "_${tbl}_new";
   if ( grep { $_ eq '--no-drop-new-table' } @$cmds ) {
      unshift @$orig_tbls, [$new_tbl];
   }

   ($output, $exit) = full_output(
      sub { pt_online_schema_change::main(
         @args,
         '--print',
         "$dsn,D=$db,t=$tbl",
         @$cmds,
      )},
      stderr => 1,
   );

   my $new_ddl = $tp->get_create_table($master_dbh, $db, $tbl);
   my $new_tbl_struct = $tp->parse($new_ddl);
   my $fail    = 0;

   is(
      $exit,
      0,
      "$name exit 0"
   ) or $fail = 1;

   # There should be no new or missing tables.
   my $new_tbls = $master_dbh->selectall_arrayref("SHOW TABLES FROM `$db`");
   is_deeply(
      $new_tbls,
      $orig_tbls,
      "$name tables"
   ) or $fail = 1;

   # Rows in the original and new table should be identical.
   my $new_rows = $master_dbh->selectall_arrayref("SELECT $cols FROM $table ORDER BY `$pk_col`");
   is_deeply(
      $new_rows,
      $orig_rows,
      "$name rows"
   ) or $fail = 1;

   if ( grep { $_ eq '--preserve-triggers' } @$cmds && !$delete_triggers) {
      my $new_triggers = $master_dbh->selectall_arrayref($triggers_sql);
      is_deeply(
         $new_triggers,
         $orig_triggers,
         "$name triggers still exist"
      ) or $fail = 1;
   }

   if ( grep { $_ eq '--no-drop-new-table' } @$cmds ) {
      $new_rows = $master_dbh->selectall_arrayref(
         "SELECT $cols FROM `$db`.`$new_tbl` ORDER BY `$pk_col`");
      is_deeply(
         $new_rows,
         $orig_rows,
         "$name new table rows"
      ) or $fail = 1;
   }

   my $new_max_id = $master_dbh->selectall_arrayref(
      "SELECT MAX(`$pk_col`) FROM `$db`.`$tbl`");
   is(
      $orig_max_id->[0]->[0],
      $new_max_id->[0]->[0],
      "$name MAX(pk_col)"
   ) or $fail = 1;

   my ($new_auto_inc) = $new_ddl =~ m/\s+AUTO_INCREMENT=(\d+)\s+/;
   is(
      $orig_auto_inc,
      $new_auto_inc,
      "$name AUTO_INCREMENT=" . ($orig_auto_inc || '<unknown>')
   ) or $fail = 1;

   # Check if the ALTER was actually done.
   if ( $test_type eq 'drop_col' ) {
      my $col = $q->quote($args{drop_col});

      if ( grep { $_ eq '--dry-run' } @$cmds ) {
         like(
            $new_ddl,
            qr/^\s+$col\s+/m,
            "$name ALTER DROP COLUMN=$args{drop_col} (dry run)"
         ) or $fail = 1;
      }
      else {
         unlike(
            $new_ddl,
            qr/^\s+$col\s+/m,
            "$name ALTER DROP COLUMN=$args{drop_col}"
         ) or $fail = 1;
      }
   }
   elsif ( $test_type eq 'add_col' ) {
      if ( $args{no_change} ) {
         ok(
            !$new_tbl_struct->{is_col}->{$args{new_col}},
            "$name $args{new_col} not added"
         );
      }
      else {
         ok(
            $new_tbl_struct->{is_col}->{$args{new_col}},
            "$name $args{new_col} added"
         );
      }
   }
   elsif ( $test_type eq 'new_engine' ) {
      my $new_engine = lc($args{new_engine});
      die "I need a new_engine argument" unless $new_engine;
      my $rows = $master_dbh->selectall_hashref(
         "SHOW TABLE STATUS FROM `$db`", "name");
      is(
         lc($rows->{$tbl}->{engine}),
         $new_engine,
         "$name ALTER ENGINE=$args{new_engine}"
      ) or $fail = 1;

   }
 
   if ( $fk_method ) {
      my @new_fks;
      my $rebuild_method = 0;

      foreach my $tbl ( @$orig_tbls ) {
         my $fks = $tp->get_fks(
            $tp->get_create_table($master_dbh, $db, $tbl->[0]));

         # The tool does not use the same/original fk name,
         # it appends a single _.  So we need to strip this
         # to compare the original fks to the new fks.
         # if ( $fk_method eq 'rebuild_constraints' ) {
         if ( $fk_method eq 'rebuild_constraints'
               || $table_name eq $tbl->[0] ) {
            my %new_fks = map {
               my $real_fk_name = $_;
               my $fk_name      = $_;
               if ( $fk_name =~ s/^_// && $table_name ne $tbl->[0] ) {
                  $rebuild_method = 1;
               }
               $fks->{$real_fk_name}->{name} =~ s/^_//;
               $fks->{$real_fk_name}->{ddl}  =~ s/`$real_fk_name`/`$fk_name`/;
               $fk_name => $fks->{$real_fk_name};
            } keys %$fks;
            push @new_fks, \%new_fks;
         }
         else {
            # drop_swap
            push @new_fks, $fks;
         }
      }

      if ( grep { $_ eq '--execute' } @$cmds ) {
         ok(
              $fk_method eq 'rebuild_constraints' &&  $rebuild_method ? 1
            : $fk_method eq 'drop_swap'           && !$rebuild_method ? 1
            :                                                           0,
            "$name FK $fk_method method"
         );
      }

      is_deeply(
         \@new_fks,
         \@orig_fks,
         "$name FK constraints"
      ) or $fail = 1;

      # Go that extra mile and verify that the fks are actually
      # still functiona: i.e. that they'll prevent us from delete
      # a parent row that's being referenced by a child.
      my $sql = "DELETE FROM $table WHERE $pk_col=1 LIMIT 1";
      eval {
         $master_dbh->do($sql);
      };
      like(
         $EVAL_ERROR,
         qr/foreign key constraint fails/,
         "$name FK constraints still hold"
      ) or $fail = 1;
   }

   if ( $fail ) {
      diag("Output from failed test:\n$output");
   }
   elsif ( $args{output} ) {
      warn $output;
   }

   return;
}
# #############################################################################
# Tests for --preserve-triggers option
# #############################################################################

SKIP: {
   skip 'Sandbox MySQL version should be >= 5.7' unless $sandbox_version ge '5.7';

    test_alter_table(
       name       => 'Basic --preserve-triggers',
       table      => "pt_osc.account",
       pk_col     => "id",
       file       => "triggers.sql",
       test_type  => "add_col",
       new_col    => "foo",
       cmds       => [
          qw(--execute --preserve-triggers), '--alter', 'ADD COLUMN foo INT',
       ],
    );
    
    test_alter_table(
       name       => "--preserve-triggers: after triggers",
       table      => "test.t1",
       pk_col     => "id",
       file       => "after_triggers.sql",
       test_type  => "add_col",
       new_col    => "foo3",
       cmds       => [
          qw(--execute --preserve-triggers --alter-foreign-keys-method rebuild_constraints), '--alter', 'ADD COLUMN foo3 INT',
       ],
    );
    
    
    $sb->load_file('master', "$sample/after_triggers.sql");

    ($output, $exit) = full_output(
       sub { pt_online_schema_change::main(@args,
          "$dsn,D=test,t=t1", 
          qw(--execute --preserve-triggers), '--alter', 'DROP COLUMN f1')
       },
       stderr => 1,
    );
    
    isnt(
          $exit,
          0,
          "--preserve-triggers cannot drop column used by trigger",
    );

    like( 
          $output,
          qr/Check if all fields referenced by the trigger still exists after the operation you are trying to apply/,
          "--preserve-triggers: message if try to drop a field used by triggers",
    );

    ($output, $exit) = full_output(
       sub { pt_online_schema_change::main(@args,
          "$dsn,D=test,t=t1", 
          qw(--execute --no-swap-tables --preserve-triggers), '--alter', 'ADD COLUMN foo INT')
       },
       stderr => 1,
    );
    
    is(
       $exit,
       0,
       "--preserve-triggers --no-swap-tables exit status",
    );
    
    $sb->load_file('master', "$sample/after_triggers.sql");

    ($output, $exit) = full_output(
       sub { pt_online_schema_change::main(@args,
          "$dsn,D=test,t=t1", 
          qw(--execute --no-drop-old-table --preserve-triggers), '--alter', 'ADD COLUMN foo INT')
       },
       stderr => 1,
    );
    
    is(
          $exit,
          0,
          "--preserve-triggers --no-drop-old-table exit status",
    );

    my $rows = $master_dbh->selectall_arrayref("SHOW TABLES LIKE '%t1%'");
    is_deeply(
          $rows,
          [ [ '_t1_old' ], [ 't1' ] ],
          "--preserve-triggers --no-drop-old-table original & new tables still exists",
    );

    ($output, $exit) = full_output(
       sub { pt_online_schema_change::main(@args,
          "$dsn,D=pt_osc,t=t", 
          qw(--execute --no-drop-triggers --preserve-triggers), '--alter', 'ADD COLUMN foo INT')
       },
       stderr => 1,
    );
    
    isnt(
          $exit,
          0,
          "--preserve-triggers cannot be used --no-drop-triggers",
    );

    test_alter_table(
       name        => "Basic FK auto --execute",
       table       => "pt_osc.country",
       pk_col      => "country_id",
       file        => "basic_with_fks.sql",
       test_type   => "drop_col",
       drop_col    => "last_update",
       check_fks   => "rebuild_constraints",
       cmds        => [
       qw(
          --execute
          --alter-foreign-keys-method rebuild_constraints
          --preserve-triggers
       ),
          '--alter', 'DROP COLUMN last_update',
       ],
    );

    test_alter_table(
       name            => "--preserve-triggers: --no-swap-tables --drop-new-table",
       table           => "test.t1",
       pk_col          => "id",
       file            => "after_triggers.sql",
       test_type       => "add_col",
       new_col         => "foo4",
       no_change       => 1,
       delete_triggers => 1,
       cmds            => [
                             qw(--execute --preserve-triggers --no-swap-tables --drop-new-table 
                                --alter-foreign-keys-method rebuild_constraints),
                             '--alter', 'ADD COLUMN foo4 INT',
                          ],
    );
    
}

diag("Reloading sakila");
my $master_port = $sb->port_for('master');
system "$trunk/sandbox/load-sakila-db $master_port &";

$sb->do_as_root("master", q/GRANT REPLICATION SLAVE ON *.* TO 'slave_user'@'%' IDENTIFIED BY 'slave_password'/);
$sb->do_as_root("master", q/set sql_log_bin=0/);
$sb->do_as_root("master", q/DROP USER 'slave_user'/);
$sb->do_as_root("master", q/set sql_log_bin=1/);

test_alter_table(
   name       => "--slave-user --slave-password",
   file       => "basic_no_fks_innodb.sql",
   table      => "pt_osc.t",
   test_type  => "add_col",
   new_col    => "bar",
   cmds       => [
         qw(--execute --slave-user slave_user --slave-password slave_password), '--alter', 'ADD COLUMN bar INT',
   ],
);
# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
#
done_testing;
