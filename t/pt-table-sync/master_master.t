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
require "$trunk/bin/pt-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

plan tests => 11;

# #############################################################################
# Ensure that syncing source-source works OK
# #############################################################################

# Start up 12348 <-> 12349
diag('Starting source-source servers...');
diag(`$trunk/sandbox/start-sandbox source-source 12348 12349`);
my $source1_dbh = $sb->get_dbh_for('source1');
my $source2_dbh = $sb->get_dbh_for('source2');

# Load some tables and data (on both, since they're source-source).
$sb->load_file("source1", "t/pt-table-sync/samples/before.sql");
$sb->wait_for_replicas();
$sb->wait_for_replicas(
                     source => 'source1',
                     replica => 'source2',
                  );

# Make source2 different from source1.  So source2 has the _correct_ data,
# and the sync below will make source1 have that data too.
$source2_dbh->do("set sql_log_bin=0");
$source2_dbh->do("update test.test1 set b='mm' where a=1");
$source2_dbh->do("set sql_log_bin=1");

# This will make source1's data match the changed, correcct data on source2
# (that is _not_ a typo). The sync direction is therefore source2 -> source1
# because, given the command below, the given host source1 and with
# --sync-to-source that makes source2 "the" source with the correct data.
my $exit_status = 0;
my $output = output(
   sub {
      $exit_status = pt_table_sync::main(
         qw(--no-check-replica --sync-to-source --print --execute),
         "h=127.0.0.1,P=12348,u=msandbox,p=msandbox,D=test,t=test1")
   },
   stderr => 1
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

unlike(
   $output,
   qr/Option --sync-to-master is deprecated and will be removed in future versions./,
   'Deprecation warning not printed when option --sync-to-source provided'
) or diag($output);

unlike(
   $output,
   qr/Option --\[no\]check-slave is deprecated and will be removed in future versions./,
   'Deprecation warning not printed when option --no-check-replica provided'
) or diag($output);


PerconaTest::wait_for_table($source1_dbh, "test.test1", "a=1 and b='mm'");
my $rows = $source1_dbh->selectall_arrayref("SELECT * FROM test.test1");
is_deeply(
   $rows,
   [ [1, 'mm'], [2, 'ca'] ],
   "Diff row synced on source1"
); 

diag('Stopping source-source servers...');
diag(`$trunk/sandbox/stop-sandbox 12348 12349 >/dev/null`);
# #############################################################################
# Repeat the test with deprecated options.
# #############################################################################

# Start up 12348 <-> 12349
diag('Starting source-source servers...');
diag(`$trunk/sandbox/start-sandbox source-source 12348 12349`);
$source1_dbh = $sb->get_dbh_for('source1');
$source2_dbh = $sb->get_dbh_for('source2');

$sb->load_file("source1", "t/pt-table-sync/samples/before.sql");
$sb->wait_for_replicas();
$sb->wait_for_replicas(
                     source => 'source1',
                     replica => 'source2',
                  );

# Make source2 different from source1.  So source2 has the _correct_ data,
# and the sync below will make source1 have that data too.
$source2_dbh->do("set sql_log_bin=0");
$source2_dbh->do("update test.test1 set b='mm' where a=1");
$source2_dbh->do("set sql_log_bin=1");

# This will make source1's data match the changed, correcct data on source2
# (that is _not_ a typo). The sync direction is therefore source2 -> source1
# because, given the command below, the given host source1 and with
# --sync-to-source that makes source2 "the" source with the correct data.
$exit_status = 0;
$output = output(
   sub {
      $exit_status = pt_table_sync::main(
         qw(--no-check-slave --sync-to-master --print --execute),
         "h=127.0.0.1,P=12348,u=msandbox,p=msandbox,D=test,t=test1")
   },
   stderr =>1
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

like(
   $output,
   qr/Option --sync-to-master is deprecated and will be removed in future versions./,
   'Deprecation warning printed when option --sync-to-master provided'
) or diag($output);

like(
   $output,
   qr/Option --\[no\]check-slave is deprecated and will be removed in future versions./,
   'Deprecation warning printed when option --no-check-slave provided'
) or diag($output);


PerconaTest::wait_for_table($source1_dbh, "test.test1", "a=1 and b='mm'");
$rows = $source1_dbh->selectall_arrayref("SELECT * FROM test.test1");
is_deeply(
   $rows,
   [ [1, 'mm'], [2, 'ca'] ],
   "Diff row synced on source1"
);

diag('Stopping source-source servers...');
diag(`$trunk/sandbox/stop-sandbox 12348 12349 >/dev/null`);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
