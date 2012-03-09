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

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 23;
}

my $output  = "";
my $cnf     = '/tmp/12345/my.sandbox.cnf';
my @args    = ('-F', $cnf, '--execute');
my $exit    = 0;
my $rows;

$sb->load_file('master', "t/pt-online-schema-change/samples/small_table.sql");
$dbh->do('use mkosc');

# #############################################################################
# Tool shouldn't run without --execute (bug 933232).
# #############################################################################
$output = output(
   sub { pt_online_schema_change::main('h=127.1,P=12345,u=msandbox,p=msandbox,D=mkosc,t=a') },
);

like(
   $output,
   qr/you did not specify --execute/,
   "Doesn't run without --execute"
);

# #############################################################################
# --check-tables-and-exit
# #############################################################################
eval {
   $exit = pt_online_schema_change::main(@args,
      'D=mkosc,t=a', qw(--check-tables-and-exit --quiet))
};

is(
   $EVAL_ERROR,
   "",
   "--check-tables-and-exit"
);

is(
   $exit,
   0,
   "Exit status 0"
);

# #############################################################################
# --cleanup-and-exit
# #############################################################################
eval {
   $exit = pt_online_schema_change::main(@args,
      'D=mkosc,t=a', qw(--cleanup-and-exit --quiet))
};

is(
   $EVAL_ERROR,
   "",
   "--cleanup-and-exit",
);

is(
   $exit,
   0,
   "Exit status 0"
);

# #############################################################################
# The most basic: copy, alter and rename a small table that's not even active.
# #############################################################################

output(
   sub { $exit = pt_online_schema_change::main(@args,
      'D=mkosc,t=a', qw(--alter ENGINE=InnoDB)) },
);

$rows = $dbh->selectall_hashref('show table status from mkosc', 'name');
is(
   $rows->{a}->{engine},
   'InnoDB',
   "New table ENGINE=InnoDB"
);

is(
   $rows->{__old_a}->{engine},
   'MyISAM',
   "Kept old table, ENGINE=MyISAM"
);

my $org_rows = $dbh->selectall_arrayref('select * from mkosc.__old_a order by i');
my $new_rows = $dbh->selectall_arrayref('select * from mkosc.a order by i');
is_deeply(
   $new_rows,
   $org_rows,
   "New tables rows identical to old table rows"
);

is(
   $exit,
   0,
   "Exit status 0"
);

# #############################################################################
# No --alter and --drop-old-table.
# #############################################################################
$dbh->do('drop table if exists mkosc.__old_a');  # from previous run
$sb->load_file('master', "t/pt-online-schema-change/samples/small_table.sql");

output(
   sub { $exit = pt_online_schema_change::main(@args,
      'D=mkosc,t=a', qw(--drop-old-table)) },
);

$rows = $dbh->selectall_hashref('show table status from mkosc', 'name');
is(
   $rows->{a}->{engine},
   'MyISAM',
   "No --alter, new table still ENGINE=MyISAM"
);

ok(
   !exists $rows->{__old_a},
   "--drop-old-table"
);

$new_rows = $dbh->selectall_arrayref('select * from mkosc.a order by i');
is_deeply(
   $new_rows,
   $org_rows,  # from previous run since old table was dropped this run
   "New tables rows identical to old table rows"
);

is(
   $exit,
   0,
   "Exit status 0"
);

# ############################################################################
# Alter a table with foreign keys.
# ############################################################################

# The tables we're loading have fk constraints like:
# country
#   ^- city (on update cascade)
#        ^- address (on update cascade)

############################
# rebuild_constraints method
############################
$sb->load_file('master', "t/pt-online-schema-change/samples/fk_tables_schema.sql");

# city has a fk constraint on country, so get its original table def.
my $orig_table_def = $dbh->selectrow_hashref('show create table mkosc.city')->{'create table'};

# Alter the parent table.  The error we need to avoid is:
# DBD::mysql::db do failed: Cannot delete or update a parent row:
# a foreign key constraint fails [for Statement "DROP TABLE
# `mkosc`.`__old_country`"]
output(
   sub { $exit = pt_online_schema_change::main(@args,
      'D=mkosc,t=country', qw(--child-tables auto_detect --drop-old-table),
      qw(--update-foreign-keys-method rebuild_constraints)) },
);
is(
   $exit,
   0,
   "Exit status 0 (rebuild_constraints method)"
);

$rows = $dbh->selectall_arrayref('show tables from mkosc like "\_\_%"');
is_deeply(
   $rows,
   [],
   "Old table dropped (rebuild_constraints method)"
);

# Get city's table def again and verify that its fk constraint still
# references country.  When country was renamed to __old_country, MySQL
# also updated city's fk constraint to __old_country.  We should have
# dropped and re-added that constraint exactly, changing only __old_country
# to country, like it originally was.
my $new_table_def = $dbh->selectrow_hashref('show create table mkosc.city')->{'create table'};
is(
   $new_table_def,
   $orig_table_def,
   "Updated child table foreign key constraint (rebuild_constraints method)"
);

#######################
# drop_old_table method 
#######################
$sb->load_file('master', "t/pt-online-schema-change/samples/fk_tables_schema.sql");

$orig_table_def = $dbh->selectrow_hashref('show create table mkosc.city')->{'create table'};

output(
   sub { $exit = pt_online_schema_change::main(@args,
      'D=mkosc,t=country', qw(--child-tables auto_detect),
      qw(--update-foreign-keys-method drop_old_table)) },
);
is(
   $exit,
   0,
   "Exit status 0 (drop_old_table method)"
);

$rows = $dbh->selectall_arrayref('show tables from mkosc like "\_\_%"');
is_deeply(
   $rows,
   [],
   "Old table dropped (drop_old_table method)"
) or print Dumper($rows);

$new_table_def = $dbh->selectrow_hashref('show create table mkosc.city')->{'create table'};
is(
   $new_table_def,
   $orig_table_def,
   "Updated child table foreign key constraint (drop_old_table method)"
);

# #############################################################################
# Alter tables with columns with resvered words and spaces.
# #############################################################################
sub test_table {
   my (%args) = @_;
   my ($file, $name) = @args{qw(file name)};

   $sb->load_file('master', "t/lib/samples/osc/$file");
   PerconaTest::wait_for_table($dbh, "osc.t", "id=5");
   PerconaTest::wait_for_table($dbh, "osc.__new_t");
   $dbh->do('use osc');
   $dbh->do("DROP TABLE IF EXISTS osc.__new_t");

   $org_rows = $dbh->selectall_arrayref('select * from osc.t order by id');

   output(
      sub { $exit = pt_online_schema_change::main(@args,
         'D=osc,t=t', qw(--alter ENGINE=InnoDB)) },
   );

   $new_rows = $dbh->selectall_arrayref('select * from osc.t order by id');

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
$sb->wipe_clean($dbh);
exit;
