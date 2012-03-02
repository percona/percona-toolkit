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
diag(`$trunk/sandbox/start-sandbox master 12348 >/dev/null`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('master');
my $dbh2 = $sb->get_dbh_for('master1');

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$dbh2 ) {
   plan skip_all => 'Cannot connect to second sandbox master';
}
else {
   plan tests => 12;
}

my @host_args = ('h=127.1,P=12345', 'P=12348');
my @op_args   = (qw(-u msandbox -p msandbox),
                 '--compare', 'results,warnings',
                 '--zero-query-times',
);
my @args      = (@host_args, @op_args);
my $sample    = "t/pt-upgrade/samples";
my $log       = "$trunk/$sample";

# ###########################################################################
# Basic run.
# ###########################################################################
$sb->load_file('master',  "$sample/001/tables.sql");
$sb->load_file('master1', "$sample/001/tables.sql");

ok(
   no_diff(
      sub { pt_upgrade::main(@args, "$log/001/select-one.log") },
      "$sample/001/select-one.txt",
   ),
   'Report for a single query (checksum method)'
);

ok(
   no_diff(
      sub { pt_upgrade::main(@args, "$log/001/select-everyone.log") },
      "$sample/001/select-everyone.txt"
   ),
   'Report for multiple queries (checksum method)'
);

ok(
   no_diff(
      sub { pt_upgrade::main(@args, "$trunk/$sample/001/select-one.log",
         "--compare-results-method", "rows") },
      "$sample/001/select-one-rows.txt"
   ),
   'Report for a single query (rows method)'
);

ok(
   no_diff(
      sub { pt_upgrade::main(@args, "$trunk/$sample/001/select-everyone.log",
         "--compare-results-method", "rows") },
      "$sample/001/select-everyone-rows.txt"
   ),
   'Report for multiple queries (rows method)'
);

ok(
   no_diff(
      sub { pt_upgrade::main(@args, "$trunk/$sample/001/select-everyone.log",
         "--reports", "queries,differences,errors") },
      "$sample/001/select-everyone-no-stats.txt"
   ),
   'Report without statistics'
);

ok(
   no_diff(
      sub { pt_upgrade::main(@args, "$trunk/$sample/001/select-everyone.log",
         "--reports", "differences,errors,statistics") },
      "$sample/001/select-everyone-no-queries.txt"
   ),
   'Report without per-query reports'
);

$sb->wipe_clean($dbh1);
$sb->wipe_clean($dbh2);

# #############################################################################
# Issue 951: mk-upgrade "I need a db argument" error with
# compare-results-method=rows
# #############################################################################
$sb->load_file('master',  "$sample/002/tables.sql");
$sb->load_file('master1', "$sample/002/tables.sql");

# Make a difference on one host so diff_rows() is called.
$dbh1->do('insert into test.t values (5)');

ok(
   no_diff(
      sub { pt_upgrade::main(@op_args, "$log/002/no-db.log",
         'h=127.1,P=12345,D=test', 'P=12348,D=test',
         qw(--compare-results-method rows --temp-database test)) },
      "$sample/002/report-01.txt",
   ),
   'No db, compare results row, DSN D, --temp-database (issue 951)'
);

$sb->load_file('master',  "$sample/002/tables.sql");
$sb->load_file('master1', "$sample/002/tables.sql");
$dbh1->do('insert into test.t values (5)');

ok(
   no_diff(
      sub { pt_upgrade::main(@op_args, "$log/002/no-db.log",
         'h=127.1,P=12345,D=test', 'P=12348,D=test',
         qw(--compare-results-method rows --temp-database tmp_db)) },
      "$sample/002/report-01.txt",
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

$sb->wipe_clean($dbh1);
$sb->wipe_clean($dbh2);

# #############################################################################
# Bug 926598: DBD::mysql bug causes pt-upgrade to use wrong 
# precision (M) and scale (D) 
# #############################################################################
$sb->load_file('master',  "$sample/003/tables.sql");
$sb->load_file('master1', "$sample/003/tables.sql");

# Make a difference on one host so diff_rows() is called.
$dbh1->do('insert into test.t values (4, 1.00)');

ok(
   no_diff(
      sub { pt_upgrade::main(@args, "$log/003/double.log",
         qw(--compare-results-method rows)) },
      "$sample/003/report001.txt",
   ),
   'M, D diff (bug 926598)',
);

my $row = $dbh1->selectrow_arrayref("show create table test.mk_upgrade_left");
like(
   $row->[1],
   qr/`SUM\(total\)`\s+double\sDEFAULT/,
   "No M,D in table def (bug 926598)"
);

# #############################################################################
# Done.
# #############################################################################
diag(`rm /tmp/left-outfile.txt /tmp/right-outfile.txt 2>/dev/null`);
$sb->wipe_clean($dbh1);
$sb->wipe_clean($dbh2);
exit;
