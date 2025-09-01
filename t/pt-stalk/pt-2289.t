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

$retval = system("$trunk/bin/pt-stalk --no-stalk --pid $pid_file --log $log_file --dest $dest --iterations 1 -- --defaults-file=$cnf >$log_file 2>&1");

PerconaTest::wait_until(sub { !-f $pid_file });

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


# #############################################################################
# Done.
# #############################################################################

cleanup();
diag(`rm -rf $dest 2>/dev/null`);
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
