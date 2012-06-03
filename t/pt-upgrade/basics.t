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
require "$trunk/bin/pt-upgrade";

# This runs immediately if the server is already running, else it starts it.
diag(`$trunk/sandbox/start-sandbox master 12347 >/dev/null`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('master');
my $dbh2 = $sb->get_dbh_for('slave2');

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$dbh2 ) {
   plan skip_all => 'Cannot connect to second sandbox master';
}
else {
   plan tests => 11;
}

$sb->load_file('master', 't/pt-upgrade/samples/001/tables.sql');
$sb->load_file('slave2', 't/pt-upgrade/samples/001/tables.sql');

my $cmd    = "$trunk/bin/pt-upgrade h=127.1,P=12345,u=msandbox,p=msandbox P=12347 --compare results,warnings --zero-query-times";
my @args   = ('--compare', 'results,warnings', '--zero-query-times');
my $sample = "$trunk/t/pt-upgrade/samples/";

ok(
   no_diff(
      "$cmd $trunk/t/pt-upgrade/samples/001/select-one.log",
      't/pt-upgrade/samples/001/select-one.txt'
   ),
   'Report for a single query (checksum method)'
);

ok(
   no_diff(
      "$cmd $trunk/t/pt-upgrade/samples/001/select-everyone.log",
      't/pt-upgrade/samples/001/select-everyone.txt'
   ),
   'Report for multiple queries (checksum method)'
);

ok(
   no_diff(
      "$cmd $trunk/t/pt-upgrade/samples/001/select-one.log --compare-results-method rows",
      't/pt-upgrade/samples/001/select-one-rows.txt'
   ),
   'Report for a single query (rows method)'
);

ok(
   no_diff(
      "$cmd $trunk/t/pt-upgrade/samples/001/select-everyone.log --compare-results-method rows",
      't/pt-upgrade/samples/001/select-everyone-rows.txt'
   ),
   'Report for multiple queries (rows method)'
);

ok(
   no_diff(
      "$cmd --reports queries,differences,errors $trunk/t/pt-upgrade/samples/001/select-everyone.log",
      't/pt-upgrade/samples/001/select-everyone-no-stats.txt'
   ),
   'Report without statistics'
);

ok(
   no_diff(
      "$cmd --reports differences,errors,statistics $trunk/t/pt-upgrade/samples/001/select-everyone.log",
      't/pt-upgrade/samples/001/select-everyone-no-queries.txt'
   ),
   'Report without per-query reports'
);

# #############################################################################
# Issue 951: mk-upgrade "I need a db argument" error with
# compare-results-method=rows
# #############################################################################
$sb->load_file('master', 't/pt-upgrade/samples/002/tables.sql');
$sb->load_file('slave2', 't/pt-upgrade/samples/002/tables.sql');

# Make a difference so diff_rows() is called.
$dbh1->do('insert into test.t values (5)');

ok(
   no_diff(
      sub { pt_upgrade::main(@args,
         'h=127.1,P=12345,u=msandbox,p=msandbox,D=test', 'P=12347,D=test',
         "$sample/002/no-db.log",
         qw(--compare-results-method rows --temp-database test)) },
      't/pt-upgrade/samples/002/report-01.txt',
   ),
   'No db, compare results row, DSN D, --temp-database (issue 951)'
);

$sb->load_file('master', 't/pt-upgrade/samples/002/tables.sql');
$sb->load_file('slave2', 't/pt-upgrade/samples/002/tables.sql');
$dbh1->do('insert into test.t values (5)');

ok(
   no_diff(
      sub { pt_upgrade::main(@args,
         'h=127.1,P=12345,u=msandbox,p=msandbox,D=test', 'P=12347,D=test',
         "$sample/002/no-db.log",
         qw(--compare-results-method rows --temp-database tmp_db)) },
      't/pt-upgrade/samples/002/report-01.txt',
   ),
   'No db, compare results row, DSN D'
);

is_deeply(
   $dbh1->selectall_arrayref('show tables from `test`'),
   [['t']],
   "Didn't create temp table in event's db"
);

is_deeply(
   $dbh1->selectall_arrayref('show tables from `tmp_db`'),
   [['mk_upgrade_left']],
   "Createed temp table in --temp-database"
);

# #############################################################################
# Done.
# #############################################################################
diag(`rm /tmp/left-outfile.txt /tmp/right-outfile.txt 2>/dev/null`);
$sb->wipe_clean($dbh1);
$sb->wipe_clean($dbh2);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
