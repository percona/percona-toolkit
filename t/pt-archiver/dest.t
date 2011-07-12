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
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 13;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-archiver";

# Make sure load works.
$sb->create_dbs($dbh, ['test']);
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');

# Archive to another table.
$output = output(
   sub { pt_archiver::main(qw(--where 1=1), "--source", "D=test,t=table_1,F=$cnf", qw(--dest t=table_2)) },
);
is($output, '', 'No output for archiving to another table');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_1"`;
is($output + 0, 0, 'Purged all rows ok');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_2"`;
is($output + 0, 4, 'Found rows in new table OK when archiving to another table');

# Archive only some columns to another table.
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$output = output(
   sub { pt_archiver::main("-c", "b,c", qw(--where 1=1), "--source", "D=test,t=table_1,F=$cnf", qw(--dest t=table_2)) },
);
is($output, '', 'No output for archiving only some cols to another table');
$rows = $dbh->selectall_arrayref("select * from test.table_1");
ok(scalar @$rows == 0, 'Purged all rows ok');
# This test has been changed. I manually examined the tables before
# and after the archive operation and I am convinced that the original
# expected output was incorrect.
$rows = $dbh->selectall_arrayref("select * from test.table_2", { Slice => {}});
is_deeply(
   $rows,
   [  {  a => '1', b => '2',   c => '3', d => undef },
      {  a => '2', b => undef, c => '3', d => undef },
      {  a => '3', b => '2',   c => '3', d => undef },
      {  a => '4', b => '2',   c => '3', d => undef },
   ],
   'Found rows in new table OK when archiving only some columns to another table');


# Archive to another table with autocommit
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$output = output(
   sub { pt_archiver::main(qw(--where 1=1 --txn-size 0), "--source", "D=test,t=table_1,F=$cnf", qw(--dest t=table_2)) },
);
is($output, '', 'Commit every 0 rows worked OK');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_1"`;
is($output + 0, 0, 'Purged all rows ok');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_2"`;
is($output + 0, 4, 'Found rows in new table OK when archiving to another table with autocommit');

# Archive to another table with commit every 2 rows
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$output = output(
   sub { pt_archiver::main(qw(--where 1=1 --txn-size 2), "--source", "D=test,t=table_1,F=$cnf", qw(--dest t=table_2)) },
);
is($output, '', 'Commit every 2 rows worked OK');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_1"`;
is($output + 0, 0, 'Purged all rows ok');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_2"`;
is($output + 0, 4, 'Found rows in new table OK when archiving to another table with commit every 2 rows');

# Test that table with many rows can be archived to table with few
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$output = output(
   sub { pt_archiver::main(qw(--where 1=1 --dest t=table_4 --no-check-columns), "--source", "D=test,t=table_1,F=$cnf") },
);
$output = `/tmp/12345/use -N -e "select sum(a) from test.table_4"`;
is($output + 0, 10, 'Rows got archived');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
