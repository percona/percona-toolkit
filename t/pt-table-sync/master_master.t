#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 4;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

# #############################################################################
# Ensure that syncing master-master works OK
# #############################################################################

# Start up 12348 <-> 12349
diag('Starting master-master servers...');
diag(`$trunk/sandbox/start-sandbox master-master 12348 12349 >/dev/null`);
my $master1_dbh = $sb->get_dbh_for('master1');
my $master2_dbh = $sb->get_dbh_for('master2');

# Load some tables and data (on both, since they're master-master).
$master1_dbh->do("CREATE DATABASE test");
$sb->load_file("master1", "t/pt-table-sync/samples/before.sql");

# Make master2 different from master1.  So master2 has the _correct_ data,
# and the sync below will make master1 have that data too.
$master2_dbh->do("set sql_log_bin=0");
$master2_dbh->do("update test.test1 set b='mm' where a=1");
$master2_dbh->do("set sql_log_bin=1");

# This will make master1's data match the changed, correcct data on master2
# (that is _not_ a typo). The sync direction is therefore master2 -> master1
# because, given the command below, the given host master1 and with
# --sync-to-master that makes master2 "the" master with the correct data.
my $exit_status = 0;
my $output = output(
   sub {
      $exit_status = pt_table_sync::main(
         qw(--no-check-slave --sync-to-master --print --execute),
         "h=127.0.0.1,P=12348,u=msandbox,p=msandbox,D=test,t=test1")
   },
);

# 0  = ok no diffs
# 1  = error
# >1 = sum(@status{@ChangeHandler::ACTIONS})
is(
   $exit_status,
   2,
   "Exit status 2"
);

like(
   $output,
   qr/REPLACE INTO `test`\.`test1`\s*\(`a`, `b`\) VALUES\s*\('1', 'mm'\)/,
   "SQL to sync diff"
);


PerconaTest::wait_for_table($master1_dbh, "test.test1", "a=1 and b='mm'");
my $rows = $master1_dbh->selectall_arrayref("SELECT * FROM test.test1");
is_deeply(
   $rows,
   [ [1, 'mm'], [2, 'ca'] ],
   "Diff row synced on master1"
); 

diag('Stopping master-master servers...');
diag(`$trunk/sandbox/stop-sandbox 12348 12349 >/dev/null`);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
