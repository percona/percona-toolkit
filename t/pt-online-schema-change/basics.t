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
# Tool shouldn't run without --execute (bug 933232).
# #############################################################################

$sb->load_file('master', "$sample/basic_no_fks_innodb.sql");

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
      '--alter', 'drop column id') }
);

like(
   $output,
   qr/neither --dry-run nor --execute was specified/,
   "Doesn't run without --execute (bug 933232)"
) or diag($output);

my $ddl = $master_dbh->selectrow_arrayref("show create table pt_osc.t");
like(
   $ddl->[1],
   qr/^\s+["`]id["`]/m,
   "Did not alter the table"
);

is(
   $exit,
   1,
   "Exit 1"
);

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
# The most basic: alter a small table with no fks that's not active.
# #############################################################################

my $db_flavor = VersionParser->new($master_dbh)->flavor();
if ( $db_flavor =~ m/XtraDB Cluster/ ) {
   test_alter_table(
      name       => "Basic no fks --dry-run",
      table      => "pt_osc.t",
      file       => "basic_no_fks_innodb.sql",
      max_id     => 20,
      test_type  => "drop_col",
      drop_col   => "d",
      cmds       => [qw(--dry-run --alter), 'DROP COLUMN d'],
   );

   test_alter_table(
      name       => "Basic no fks --execute",
      table      => "pt_osc.t",
      # The previous test should not have modified the table.
      # file       => "basic_no_fks_innodb.sql",
      # max_id     => 20,
      test_type  => "drop_col",
      drop_col   => "d",
      cmds       => [qw(--execute --alter), 'DROP COLUMN d'],
   );

   test_alter_table(
      name       => "--execute but no --alter",
      table      => "pt_osc.t",
      file       => "basic_no_fks_innodb.sql",
       max_id     => 20,
      test_type  => "new_engine",    # When there's no change, we just check
      new_engine => "InnoDB",        # the engine as a NOP.  Any other
      cmds       => [qw(--execute)], # unintended changes are still detected.
   );
}
else {
   test_alter_table(
      name       => "Basic no fks --dry-run",
      table      => "pt_osc.t",
      file       => "basic_no_fks.sql",
      max_id     => 20,
      test_type  => "new_engine",
      new_engine => "MyISAM",
      cmds       => [qw(--dry-run --alter ENGINE=InnoDB)],
   );

   test_alter_table(
      name       => "Basic no fks --execute",
      table      => "pt_osc.t",
      # The previous test should not have modified the table.
      # file       => "basic_no_fks.sql",
      # max_id     => 20,
      test_type  => "new_engine",
      new_engine => "InnoDB",
      cmds       => [qw(--execute --alter ENGINE=InnoDB)],
   );

   test_alter_table(
      name       => "--execute but no --alter",
      table      => "pt_osc.t",
      file       => "basic_no_fks.sql",
       max_id     => 20,
      test_type  => "new_engine",
      new_engine => "MyISAM",
      cmds       => [qw(--execute)],
   );
}

# ############################################################################
# Alter a table with foreign keys.
# ############################################################################

# The tables we're loading have fk constraints like:
# country <-- city <-- address

# rebuild_constraints method -- This parses the fk constraint ddls from
# the create table ddl, rewrites them, then does an alter table on the
# child tables so they point back to the original table name.

test_alter_table(
   name       => "Basic FK rebuild --dry-run",
   table      => "pt_osc.country",
   pk_col     => "country_id",
   file       => "basic_with_fks.sql",
   test_type  => "drop_col",
   drop_col   => "last_update",
   check_fks  => "rebuild_constraints",
   cmds       => [
   qw(
      --dry-run
      --alter-foreign-keys-method rebuild_constraints
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

test_alter_table(
   name       => "Basic FK rebuild --execute",
   table      => "pt_osc.country",
   pk_col     => "country_id",
   test_type  => "drop_col",
   drop_col   => "last_update",
   check_fks  => "rebuild_constraints",
   cmds       => [
   qw(
      --execute
      --alter-foreign-keys-method rebuild_constraints
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

# drop_swap method -- This method tricks MySQL by disabling fk checks,
# then dropping the original table and renaming the new table in its place.
# Since fk checks were disabled, MySQL doesn't update the child table fk refs.
# Somewhat dangerous, but quick.  Downside: table doesn't exist for a moment.

test_alter_table(
   name       => "Basic FK drop_swap --dry-run",
   table      => "pt_osc.country",
   pk_col     => "country_id",
   file       => "basic_with_fks.sql",
   test_type  => "drop_col",
   drop_col   => "last_update",
   check_fks  => "drop_swap",
   cmds       => [
   qw(
      --dry-run
      --alter-foreign-keys-method drop_swap
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

test_alter_table(
   name       => "Basic FK drop_swap --execute",
   table      => "pt_osc.country",
   pk_col     => "country_id",
   test_type  => "drop_col",
   drop_col   => "last_update",
   check_fks  => "drop_swap",
   cmds       => [
   qw(
      --execute
      --alter-foreign-keys-method drop_swap
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

# Let the tool auto-determine the fk update method.  This should choose
# the rebuild_constraints method because the tables are quite small.
# This is tested by indicating the rebuild_constraints method, which
# causes the test sub to verify that the fks have leading _; they won't
# if drop_swap was used.  To verify this, change auto to drop_swap
# and this test will fail.
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
      --alter-foreign-keys-method auto
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

# Specify --alter-foreign-keys-method for a table with no child tables.
test_alter_table(
   name        => "Child table",
   table       => "pt_osc.address",
   pk_col      => "address_id",
   file        => "basic_with_fks.sql",
   test_type   => "new_engine",
   new_engine  => "innodb",
   cmds        => [
   qw(
      --execute
      --alter-foreign-keys-method auto
   ),
      '--alter', 'ENGINE=INNODB',
   ],
);

# Use drop_swap to alter address, which no other table references,
# so the tool should re-enable --swap-tables and --drop-old-table.
test_alter_table(
   name        => "Drop-swap child",
   table       => "pt_osc.address",
   pk_col      => "address_id",
   file        => "basic_with_fks.sql",
   test_type   => "drop_col",
   drop_col    => "last_update",
   cmds        => [
   qw(
      --execute
      --alter-foreign-keys-method drop_swap
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

# Alter city and verify that its fk to country still exists.
# (https://bugs.launchpad.net/percona-toolkit/+bug/969726)
test_alter_table(
   name        => "Preserve all fks",
   table       => "pt_osc.city",
   pk_col      => "city_id",
   file        => "basic_with_fks.sql",
   test_type   => "drop_col",
   drop_col    => "last_update",
   check_fks   => "rebuild_constraints",
   cmds        => [
   qw(
      --execute
      --alter-foreign-keys-method rebuild_constraints
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

SKIP: {
   skip 'Sandbox master does not have the sakila database', 7
   unless @{$master_dbh->selectcol_arrayref("SHOW DATABASES LIKE 'sakila'")};

   # This test will use the drop_swap method because the child tables
   # are large.  To prove this, change check_fks to rebuild_constraints
   # and the test will fail.
   test_alter_table(
      name        => "sakila.staff",
      table       => "sakila.staff",
      pk_col      => "staff_id",
      test_type   => "new_engine",
      new_engine  => "InnoDB",
      check_fks   => "drop_swap",
      cmds        => [
      qw(
         --chunk-size 100
         --execute
         --alter-foreign-keys-method auto
      ),
         '--alter', 'ENGINE=InnoDB'
      ],
   );

   # Restore the original fks.
   diag('Restoring sakila...');
   diag(`$trunk/sandbox/load-sakila-db 12345`);
}

# #############################################################################
# --alter-foreign-keys-method=none.  This intentionally breaks fks because
# they're not updated so they'll point to the old table that is dropped.
# #############################################################################

# Specify --alter-foreign-keys-method for a table with no child tables.
test_alter_table(
   name         => "Update fk method none",
   file         => "basic_with_fks.sql",
   table        => "pt_osc.country",
   pk_col       => "country_id",
   max_id       => 20,
   test_type    => "new_engine",
   new_engine   => "innodb",
   cmds         => [
      qw(--execute --alter-foreign-keys-method none --force --alter ENGINE=INNODB)
   ],
);

my $fks = $tp->get_fks(
   $tp->get_create_table($master_dbh, "pt_osc", "city"));
is(
   $fks->{fk_city_country}->{parent_tbl}->{tbl},
   "_country_old",
   "--alter-foreign-keys-method=none"
);

# #############################################################################
# Alter tables with columns with resvered words and spaces.
# #############################################################################
sub test_table {
   my (%args) = @_;
   my ($file, $name) = @args{qw(file name)};

   $sb->load_file('master', "t/lib/samples/osc/$file");
   $master_dbh->do('use osc');
   $master_dbh->do("DROP TABLE IF EXISTS osc.__new_t");

   my $org_rows = $master_dbh->selectall_arrayref('select * from osc.t order by id');

   ($output, $exit) = full_output(
      sub { pt_online_schema_change::main(@args,
         "$dsn,D=osc,t=t", qw(--execute --alter ENGINE=InnoDB)) },
      stderr => 1,
   );

   my $new_rows = $master_dbh->selectall_arrayref('select * from osc.t order by id');

   my $fail = 0;

   is_deeply(
      $new_rows,
      $org_rows,
      "$name rows"
   ) or $fail = 1;

   is(
      $exit,
      0,
      "$name exit status 0"
   ) or $fail = 1;

   if ( $fail ) {
      diag("Output from failed test:\n$output");
   }
}

test_table(
   file => "tbl002.sql",
   name => "Reserved word column",
);

test_table(
   file => "tbl003.sql",
   name => "Space column",
);

# #############################################################################
# --[no]swap-tables
# #############################################################################

test_alter_table(
   name       => "--no-swap-tables",
   table      => "pt_osc.t",
   file       => "basic_no_fks_innodb.sql",
   max_id     => 20,
   test_type  => "add_col",
   new_col    => "foo",
   no_change  => 1,
   cmds       => [
      qw(--execute --no-swap-tables), '--alter', 'ADD COLUMN foo INT'
   ],
);

test_alter_table(
   name       => "--no-swap-tables --no-drop-new-table",
   table      => "pt_osc.t",
   file       => "basic_no_fks_innodb.sql",
   max_id     => 20,
   test_type  => "add_col",
   new_col    => "foo",
   no_change  => 1,
   cmds       => [
      qw(--execute --no-swap-tables), '--alter', 'ADD COLUMN foo INT',
      qw(--no-drop-new-table),
   ],
);

# #############################################################################
# --statistics
# #############################################################################

$sb->load_file('master', "$sample/bug_1045317.sql");

ok(
   no_diff(
      sub { pt_online_schema_change::main(@args, "$dsn,D=bug_1045317,t=bits",
         '--dry-run', '--statistics',
         '--alter', "modify column val ENUM('M','E','H') NOT NULL")
      },
      "$sample/stats-dry-run.txt",
   ),
   "--statistics --dry-run"
) or diag($test_diff);

ok(
   no_diff(
      sub { pt_online_schema_change::main(@args, "$dsn,D=bug_1045317,t=bits",
         '--execute', '--statistics',
         '--alter', "modify column val ENUM('M','E','H') NOT NULL",
         '--recursion-method', 'none')
      },
      ($sandbox_version ge '5.5' && $db_flavor !~ m/XtraDB Cluster/
         ? "$sample/stats-execute-5.5.txt"
         : "$sample/stats-execute.txt"),
   ),
   "--statistics --execute"
) or diag($test_diff);

# #############################################################################
# --default-engine
# #############################################################################

SKIP: {
   skip "--default-engine tests require < MySQL 5.5", 1
      if $sandbox_version ge '5.5';

   # The alter doesn't actually change the engine (test_type),
   # but the --default-engine does because the table uses InnoDB
   # but MyISAM is the default engine before MySQL 5.5.
   test_alter_table(
      name       => "--default-engine",
      table      => "pt_osc.t",
      file       => "default-engine.sql",
      test_type  => "new_engine",
      new_engine => "MyISAM",
      cmds       => [
         '--default-engine',
         '--execute',
         '--alter', 'ADD INDEX (d)',
      ],
   );
}

# #############################################################################
# --new-table-name
# #############################################################################

test_alter_table(
   name       => "--new-table-name %T_foo",
   table      => "pt_osc.t",
   file       => "basic_no_fks_innodb.sql",
   max_id     => 20,
   test_type  => "add_col",
   new_col    => "foo",
   cmds       => [
      qw(--execute --new-table-name %T_foo), '--alter', 'ADD COLUMN foo INT'
   ],
);

test_alter_table(
   name       => "--new-table-name static_new",
   table      => "pt_osc.t",
   max_id     => 20,
   test_type  => "drop_col",
   drop_col   => "foo",
   new_table  => 'static_new',
   cmds       => [
      qw(--execute --new-table-name static_new), '--alter', 'DROP COLUMN foo'
   ],
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
