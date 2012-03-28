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

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-online-schema-change";

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
else {
   plan tests => 55;
}

my $q      = new Quoter();
my $tp     = new TableParser(Quoter => $q);
my @args   = qw(--lock-wait-timeout 3);
my $output = "";
my $dsn    = "h=127.1,P=12345,u=msandbox,p=msandbox";
my $exit   = 0;
my $sample = "t/pt-online-schema-change/samples";
my $rows;

# #############################################################################
# Tool shouldn't run without --execute (bug 933232).
# #############################################################################

$sb->load_file('master', "$sample/basic_no_fks.sql");
PerconaTest::wait_for_table($slave_dbh, "pt_osc.t", "id=20");

$output = output(
   sub { $exit = pt_online_schema_change::main(@args, "$dsn,t=pt_osc.t",
      '--alter', 'drop column id') }
);

like(
   $output,
   qr/neither --dry-run nor --execute was specified/,
   "Doesn't run without --execute (bug 933232)"
);

my $ddl = $master_dbh->selectrow_arrayref("show create table pt_osc.t");
like(
   $ddl->[1],
   qr/^\s+`id`/m,
   "Did not alter the table"
);

is(
   $exit,
   0,
   "Exit 0"
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
   my $pk_col     = $args{pk_col} || 'id';

   if ( my $file = $args{file} ) {
      $sb->load_file('master', "$sample/$file");
      if ( my $wait = $args{wait} ) {
         PerconaTest::wait_for_table($slave_dbh, @$wait);
      }
      else {
         PerconaTest::wait_for_table($slave_dbh, $table, "`$pk_col`=$args{max_id}");
      }
      $master_dbh->do("USE `$db`");
      $slave_dbh->do("USE `$db`");
   }

   my $ddl        = $tp->get_create_table($master_dbh, $db, $tbl);
   my $tbl_struct = $tp->parse($ddl);

   my $cols = '*';
   if ( $test_type eq 'drop_col' && !grep { $_ eq '--dry-run' } @$cmds ) {
      # Don't select the column being dropped.
      my $col = $args{drop_col};
      die "I need a drop_col argument" unless $col;
      $cols = join(', ', grep { $_ ne $col } @{$tbl_struct->{cols}});
   }
   my $orig_rows = $master_dbh->selectall_arrayref(
      "SELECT $cols FROM $table ORDER BY `$pk_col`");

   my $orig_tbls = $master_dbh->selectall_arrayref(
      "SHOW TABLES FROM `$db`");

   my @orig_fks;
   if ( $args{check_fks} ) {
      foreach my $tbl ( @$orig_tbls ) {
         my $fks = $tp->get_fks(
            $tp->get_create_table($master_dbh, $db, $tbl->[0]));
         push @orig_fks, $fks;
      }
   }

   # TODO: output() is capturing if this call dies, so if a test
   # causes it to die, the tests just stop without saying why, i.e.
   # without re-throwing the error.
   $output = output(
      sub { $exit = pt_online_schema_change::main(
         @args,
         "$dsn,D=$db,t=$tbl",
         @$cmds,
      )},
      stderr => 1,
   );

   is(
      $exit,
      0,
      "$name exit 0"
   );

   # There should be no new or missing tables.
   my $new_tbls = $master_dbh->selectall_arrayref("SHOW TABLES FROM `$db`");  
   is_deeply(
      $new_tbls,
      $orig_tbls,
      "$name tables"
   );

   # Rows in the original and new table should be identical.
   my $new_rows = $master_dbh->selectall_arrayref("SELECT * FROM $table ORDER BY `$pk_col`");
   is_deeply(
      $new_rows,
      $orig_rows,
      "$name rows"
   );

   # Check if the ALTER was actually done.
   if ( $test_type eq 'drop_col' ) {
      my $col = $q->quote($args{drop_col});
      my $ddl = $tp->get_create_table($master_dbh, $db, $tbl);
      if ( grep { $_ eq '--dry-run' } @$cmds ) {
         like(
            $ddl,
            qr/^\s+$col\s+/m,
            "$name ALTER DROP COLUMN=$args{drop_col} (dry run)"
         );
      }
      else {
         unlike(
            $ddl,
            qr/^\s+$col\s+/m,
            "$name ALTER DROP COLUMN=$args{drop_col}"
         );
      }
   }
   elsif ( $test_type eq 'add_col' ) {
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
      );

   }
 
   if ( $args{check_fks} ) {
      my @new_fks;
      foreach my $tbl ( @$orig_tbls ) {
         my $fks = $tp->get_fks(
            $tp->get_create_table($master_dbh, $db, $tbl->[0]));
         push @new_fks, $fks;
      }
      is_deeply(
         \@new_fks,
         \@orig_fks,
         "$name FK constraints"
      );

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
      );
   }

   return;
}

# #############################################################################
# The most basic: alter a small table with no fks that's not active.
# #############################################################################

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
   wait       => ["pt_osc.address", "address_id=5"],
   test_type  => "drop_col",
   drop_col   => "last_update",
   check_fks  => 1,
   cmds       => [
   qw(
      --dry-run
      --update-foreign-keys-method rebuild_constraints
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

test_alter_table(
   name       => "Basic FK rebuild --execute",
   table      => "pt_osc.country",
   pk_col     => "country_id",
   # The previous test should not have modified the table.
   # file       => "basic_with_fks.sql",
   # wait       => ["pt_osc.address", "address_id=5"],
   test_type  => "drop_col",
   drop_col   => "last_update",
   check_fks  => 1,
   cmds       => [
   qw(
      --execute
      --update-foreign-keys-method rebuild_constraints
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

# drop_swap method -- This method tricks MySQL by disabling fk checks,
# then dropping the original table and renaming the new table in its place.
# Since fk checks were disabled, MySQL doesn't update the child table fk refs.
# Somewhat dangerous, but quick.  Downside: table doesn't exist for a moment.

test_alter_table(
   name       => "Basic FK drop-swap --dry-run",
   table      => "pt_osc.country",
   pk_col     => "country_id",
   file       => "basic_with_fks.sql",
   wait       => ["pt_osc.address", "address_id=5"],
   test_type  => "drop_col",
   drop_col   => "last_update",
   check_fks  => 1,
   cmds       => [
   qw(
      --dry-run
      --update-foreign-keys-method drop_swap
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

test_alter_table(
   name       => "Basic FK drop-swap --execute",
   table      => "pt_osc.country",
   pk_col     => "country_id",
   # The previous test should not have modified the table.
   # file       => "basic_with_fks.sql",
   # wait       => ["pt_osc.address", "address_id=5"],
   test_type  => "drop_col",
   drop_col   => "last_update",
   check_fks  => 1,
   cmds       => [
   qw(
      --execute
      --update-foreign-keys-method drop_swap
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

# Let the tool auto-determine the fk update method.
test_alter_table(
   name       => "Basic FK auto --execute",
   table      => "pt_osc.country",
   pk_col     => "country_id",
   file       => "basic_with_fks.sql",
   wait       => ["pt_osc.address", "address_id=5"],
   test_type  => "drop_col",
   drop_col   => "last_update",
   check_fks  => 1,
   cmds       => [
   qw(
      --execute
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

# Specify the child tables manually.
test_alter_table(
   name       => "Basic FK with given child tables",
   table      => "pt_osc.country",
   pk_col     => "country_id",
   file       => "basic_with_fks.sql",
   wait       => ["pt_osc.address", "address_id=5"],
   test_type  => "drop_col",
   drop_col   => "last_update",
   check_fks  => 1,
   cmds       => [
   qw(
      --execute
      --child-tables city
   ),
      '--alter', 'DROP COLUMN last_update',
   ],
);

# #############################################################################
# Alter tables with columns with resvered words and spaces.
# #############################################################################
sub test_table {
   my (%args) = @_;
   my ($file, $name) = @args{qw(file name)};

   $sb->load_file('master', "t/lib/samples/osc/$file");
   PerconaTest::wait_for_table($master_dbh, "osc.t", "id=5");
   PerconaTest::wait_for_table($master_dbh, "osc.__new_t");
   $master_dbh->do('use osc');
   $master_dbh->do("DROP TABLE IF EXISTS osc.__new_t");

   my $org_rows = $master_dbh->selectall_arrayref('select * from osc.t order by id');

   output(
      sub { $exit = pt_online_schema_change::main(@args,
         "$dsn,D=osc,t=t", qw(--alter ENGINE=InnoDB)) },
   );

   my $new_rows = $master_dbh->selectall_arrayref('select * from osc.t order by id');

   is_deeply(
      $new_rows,
      $org_rows,
      "$name rows"
   );

   is(
      $exit,
      0,
      "$name exit status 0"
   );
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
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
