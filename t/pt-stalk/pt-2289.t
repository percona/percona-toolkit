#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;
use English qw(-no_match_vars);
use Test::More;
use Time::HiRes qw(sleep);

use PerconaTest;
use DSNParser;
use Sandbox;
require VersionParser;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

my $cnf      = "/tmp/12345/my.sandbox.cnf";
my $pid_file = "/tmp/pt-stalk.pid.$PID";
my $log_file = "/tmp/pt-stalk.log.$PID";
my $dest     = "/tmp/pt-stalk.collect.$PID";
my $int_file = "/tmp/pt-stalk-after-interval-sleep";
my $pid;
my $output;
my $retval;

sub cleanup {
   diag(`rm $pid_file $log_file $int_file 2>/dev/null`);
   diag(`rm -rf $dest 2>/dev/null`);
}

# ###########################################################################
# Test that it collects all data when no --skip-collection is given.
# ###########################################################################

cleanup();

# We need to enable transaction instrumentation in 5.7
if ( $sandbox_version eq '5.7' ) {
   $dbh->do("UPDATE performance_schema.setup_instruments SET enabled = 'YES'"
      . ", timed='YES' WHERE NAME IN ('transaction')");
}

# We need these to collect lock-waits
sub start_thread_pt_1897_1 {
   # this must run in a thread because we need to have an active session
   # with open transaction
   my ($dsn_opts) = @_;
   my $dp = new DSNParser(opts=>$dsn_opts);
   my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
   my $dbh = $sb->get_dbh_for('source');
   $sb->load_file('source', "t/pt-stalk/samples/PT-1897-1.sql");
}
my $thr1 = threads->create('start_thread_pt_1897_1', $dsn_opts);
$thr1->detach();
threads->yield();
sleep 1;

sub start_thread_pt_1897_2 {
   # this must run in a thread because we need to have an active session
   # with waiting transaction
   my ($dsn_opts) = @_;
   my $dp = new DSNParser(opts=>$dsn_opts);
   my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
   my $dbh = $sb->get_dbh_for('source');
   $sb->load_file('source', "t/pt-stalk/samples/PT-1897-2.sql");
}
my $thr2 = threads->create('start_thread_pt_1897_2', $dsn_opts);
$thr2->detach();
threads->yield();

$retval = system("$trunk/bin/pt-stalk --no-stalk --pid $pid_file --log $log_file --dest $dest --iterations 1 -- --defaults-file=$cnf >$log_file 2>&1");

sleep 35;
PerconaTest::kill_program(pid_file => $pid_file);

is(
   $retval >> 8,
   0,
   "Parent exit 0"
);

ok(
   -d $dest,
   "Creates --dest (collect) dir"
);

# ps-locks-transactions,thread-variables,innodbstatus,lock-waits,mysqladmin,processlist,rocksdbstatus,transactions
ok(
    glob("$dest/*-ps-locks-transactions"),
    "Collects *-ps-locks-transactions"
) or diag(`ls $dest`);

ok(
    glob("$dest/*-innodbstatus*"),
    "Collects *-innodbstatus*"
) or diag(`ls $dest`);

ok(
    glob("$dest/*-lock-waits"),
    "Collects *-lock-waits"
) or diag(`ls $dest`);

ok(
    glob("$dest/*-mysqladmin"),
    "Collects *-mysqladmin"
) or diag(`ls $dest`);

ok(
    glob("$dest/*-processlist"),
    "Collects *-processlist"
) or diag(`ls $dest`);

ok(
    glob("$dest/*-transactions"),
    "Collects *-transactions"
) or diag(`ls $dest`);

# thread-variables
ok(
    glob("$dest/*-variables"),
    "Collects *-variables"
) or diag(`ls $dest`);

$output = `cat $dest/*-variables 2>/dev/null`;
like(
   $output,
   qr/select \* from performance_schema\.variables_by_thread/,
   "Thread variables collected"
); # or diag($output);

SKIP: {
    skip "These tests require MyRocks", 1 if ( !$sb->has_engine('source', 'ROCKSDB') ) ;

    # rocksdbstatus
    ok(
        glob("$dest/*-rocksdbstatus*"),
        "Collects *-rocksdbstatus"
    ) or diag(`ls $dest`);

    cleanup();

    $retval = system("$trunk/bin/pt-stalk --no-stalk --pid $pid_file --log $log_file --dest $dest --iterations 1 --skip-collection rocksdbstatus -- --defaults-file=$cnf >$log_file 2>&1");

    sleep 5;
    PerconaTest::kill_program(pid_file => $pid_file);

    ok(
        ! glob("$dest/*-rocksdbstatus*"),
        "Does not collect *-rocksdbstatus"
    ) or diag(`ls $dest`);
}

cleanup();

$retval = system("$trunk/bin/pt-stalk --no-stalk --pid $pid_file --log $log_file --dest $dest --iterations 1 --skip-collection processlist -- --defaults-file=$cnf >$log_file 2>&1");

sleep 5;
PerconaTest::kill_program(pid_file => $pid_file);

ok(
    ! glob("$dest/*-processlist"),
    "Does not collect *-processlist"
) or diag(`ls $dest`);

cleanup();

$retval = system("$trunk/bin/pt-stalk --no-stalk --pid $pid_file --log $log_file --dest $dest --iterations 1 --skip-collection ps-locks-transactions,thread-variables,innodbstatus,mysqladmin,processlist,transactions -- --defaults-file=$cnf >$log_file 2>&1");

sleep 5;
PerconaTest::kill_program(pid_file => $pid_file);

ok(
    ! glob("$dest/*-ps-locks-transactions"),
    "Does not collect *-ps-locks-transactions"
) or diag(`ls $dest`);

ok(
    glob("$dest/*-variables"),
    "Collects *-variables"
) or diag(`ls $dest`);

$output = `cat $dest/*-variables 2>/dev/null`;
unlike(
   $output,
   qr/select \* from performance_schema\.variables_by_thread/,
   "Thread variables not collected"
); # or diag($output);

ok(
    ! glob("$dest/*-innodbstatus"),
    "Does not collect *-innodbstatus"
) or diag(`ls $dest`);

ok(
    ! glob("$dest/*-mysqladmin"),
    "Does not collect *-mysqladmin"
) or diag(`ls $dest`);

ok(
    ! glob("$dest/*-processlist"),
    "Does not collect *-processlist"
) or diag(`ls $dest`);

ok(
    ! glob("$dest/*-transactions"),
    "Does not collect *-transactions"
) or diag(`ls $dest`);

#Unsupported skip-collection value
cleanup();

$retval = system("$trunk/bin/pt-stalk --no-stalk --pid $pid_file --log $log_file --dest $dest --iterations 1 --skip-collection ps-locks-transactions,thread-variables,innodbstatus,mysqladmin,processlist,transaction -- --defaults-file=$cnf >$log_file 2>&1");

sleep 5;
PerconaTest::kill_program(pid_file => $pid_file);

is(
   $retval >> 8,
   1,
   "Parent exit 1 on unsupported --skip-collection value"
);

like(
   `cat $log_file`,
   qr/Invalid --skip-collection value: transaction, exiting./,
   "Rejects unsupported --skip-collection value"
);

cleanup();

$retval = system("$trunk/bin/pt-stalk --no-stalk --pid $pid_file --log $log_file --dest $dest --iterations 1 --skip-collection 'mysqladmin and' -- --defaults-file=$cnf >$log_file 2>&1");

sleep 5;
PerconaTest::kill_program(pid_file => $pid_file);

is(
   $retval >> 8,
   1,
   "Parent exit 1 on unsupported --skip-collection value"
);

like(
   `cat $log_file`,
   qr/Invalid --skip-collection value: mysqladmin and, exiting./,
   "Rejects unsupported --skip-collection value"
);

# #############################################################################
# Done.
# #############################################################################

cleanup();
diag(`rm -rf $dest 2>/dev/null`);
if ( $sandbox_version eq '5.7' ) {
   $dbh->do("UPDATE performance_schema.setup_instruments SET enabled = 'NO'"
      . ", timed='NO' WHERE NAME IN ('transaction')");
}

$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
