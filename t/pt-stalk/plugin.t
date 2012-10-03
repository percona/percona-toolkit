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

use PerconaTest;
use DSNParser;
use Sandbox;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $cnf      = "/tmp/12345/my.sandbox.cnf";
my $pid_file = "/tmp/pt-stalk.pid.$PID";
my $log_file = "/tmp/pt-stalk.log.$PID";
my $dest     = "/tmp/pt-stalk.collect.$PID";
my $output;
my $retval;
my $pid;

diag(`rm $pid_file 2>/dev/null`);
diag(`rm $log_file 2>/dev/null`);
diag(`mkdir $dest`);

# We'll have to watch Uptime since it's the only status var that's going
# to be predictable.
my (undef, $uptime) = $dbh->selectrow_array("SHOW STATUS LIKE 'Uptime'");
my $threshold = $uptime + 2;

$retval = system("$trunk/bin/pt-stalk --iterations 1 --dest $dest --variable Uptime --threshold $threshold --cycles 1 --run-time 2 --pid $pid_file --plugin $trunk/t/pt-stalk/samples/plugin001.sh -- --defaults-file=$cnf >$log_file 2>&1");

PerconaTest::wait_until(sub { !-f $pid_file });

is(
   $retval >> 8,
   0,
   "Exit 0"
);

foreach my $hook (qw(
   before_stalk
   before_collect
   after_collect
   after_collect_sleep
   after_stalk
)) {
   ok(
      -f "$dest/$hook",
      "$hook hook called"
   );
}

# #############################################################################
# Done.
# #############################################################################
diag(`rm $pid_file 2>/dev/null`);
diag(`rm $log_file 2>/dev/null`);
diag(`rm -rf $dest 2>/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
