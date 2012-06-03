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
else {
   plan tests => 27;
}

my $cnf      = "/tmp/12345/my.sandbox.cnf";
my $pid_file = "/tmp/pt-stalk.pid.$PID";
my $log_file = "/tmp/pt-stalk.log.$PID";
my $dest     = "/tmp/pt-stalk.collect.$PID";
my $pid;

diag(`rm $pid_file 2>/dev/null`);
diag(`rm $log_file 2>/dev/null`);
diag(`rm -rf $dest 2>/dev/null`);

# ###########################################################################
# Test that it won't run if can't connect to MySQL.
# ###########################################################################

my $retval = system("$trunk/bin/pt-stalk >$log_file 2>&1");
my $output = `cat $log_file`;

like(
   $output,
   qr/Cannot connect to MySQL/,
   "Cannot connect to MySQL"
);

is(
   $retval >> 8,
   1,
   "Exit 1"
);

# ###########################################################################
# Test that it runs and dies normally.
# ###########################################################################
diag(`rm $pid_file 2>/dev/null`);
diag(`rm $log_file 2>/dev/null`);
diag(`rm -rf $dest 2>/dev/null`);

$retval = system("$trunk/bin/pt-stalk --daemonize --pid $pid_file --log $log_file --dest $dest -- --defaults-file=$cnf");

is(
   $retval >> 8,
   0,
   "Parent exit 0"
);

PerconaTest::wait_for_files($pid_file, $log_file);
ok(
   -f $pid_file,
   "Creates PID file"
);

ok(
   -f $log_file,
   "Creates log file"
);

sleep 1;

ok(
   -d $dest,
   "Creates --dest (collect) dir"
);

chomp($pid = `cat $pid_file`);
$retval = system("kill -0 $pid");
is(
   $retval >> 0,
   0,
   "pt-stalk is running ($pid)"
);

$output = `cat $log_file`;
like(
   $output,
   qr/Check results: Threads_running=\d+, matched=no, cycles_true=0/,
   "Check results logged"
);

$retval = system("kill $pid 2>/dev/null");
is(
   $retval >> 0,
   0,
   "Killed pt-stalk"
);

sleep 1;

ok(
   ! -f $pid_file,
   "Removes PID file"
);

$output = `cat $log_file`;
like(
   $output,
   qr/Caught signal, exiting/,
   "Caught signal logged"
);

# ###########################################################################
# Test collect.
# ###########################################################################
diag(`rm $pid_file 2>/dev/null`);
diag(`rm $log_file 2>/dev/null`);
diag(`rm $dest/*   2>/dev/null`);

# We'll have to watch Uptime since it's the only status var that's going
# to be predictable.
my (undef, $uptime) = $dbh->selectrow_array("SHOW STATUS LIKE 'Uptime'");
my $threshold = $uptime + 2;

$retval = system("$trunk/bin/pt-stalk --iterations 1 --dest $dest  --variable Uptime --threshold $threshold --cycles 2 --run-time 2 --pid $pid_file -- --defaults-file=$cnf >$log_file 2>&1");

sleep 3;

$output = `cat $dest/*-trigger`;
like(
   $output,
   qr/Check results: Uptime=\d+, matched=yes, cycles_true=2/,
   "Collect triggered"
);

chomp($output = `cat $dest/*-df | grep -c '^TS'`);
is(
   $output,
   2,
   "Collect ran for --run-time"
);

ok(
   PerconaTest::not_running("pt-stalk --iterations 1"),
   "pt-stalk is not running"
);

$output = `cat $dest/*-trigger`;
like(
   $output,
   qr/pt-stalk ran with --function=status --variable=Uptime --threshold=$threshold/,
   "Trigger file logs how pt-stalk was ran"
);

chomp($output = `cat $log_file | grep 'Collector PID'`);
like(
   $output,
   qr/Collector PID \d+/,
   "Collector PID logged"
);

# ###########################################################################
# Triggered but --no-collect.
# ###########################################################################
diag(`rm $pid_file 2>/dev/null`);
diag(`rm $log_file 2>/dev/null`);
diag(`rm $dest/*   2>/dev/null`);

(undef, $uptime) = $dbh->selectrow_array("SHOW STATUS LIKE 'Uptime'");
$threshold = $uptime + 2;

$retval = system("$trunk/bin/pt-stalk --no-collect --iterations 1 --dest $dest  --variable Uptime --threshold $threshold --cycles 1 --run-time 1 --pid $pid_file -- --defaults-file=$cnf >$log_file 2>&1");

sleep 2;

$output = `cat $log_file`;
like(
   $output,
   qr/Collect triggered/,
   "Collect triggered"
);

ok(
   ! -f "$dest/*",
   "No files collected"
);

ok(
   PerconaTest::not_running("pt-stalk --no-collect"),
   "pt-stalk is not running"
);

# #############################################################################
# --config
# #############################################################################

diag(`cp $ENV{HOME}/.pt-stalk.conf $ENV{HOME}/.pt-stalk.conf.original 2>/dev/null`);
diag(`cp $trunk/t/pt-stalk/samples/config001.conf $ENV{HOME}/.pt-stalk.conf`);

system "$trunk/bin/pt-stalk --dest $dest --pid $pid_file >$log_file 2>&1 &";
PerconaTest::wait_for_files($pid_file);
sleep 1;
chomp($pid = `cat $pid_file`);
$retval = system("kill $pid 2>/dev/null");
is(
   $retval >> 0,
   0,
   "Killed pt-stalk"
);

$output = `cat $log_file`;
like(
   $output,
   qr/Check results: Aborted_connects=|variable=Aborted_connects/,
   "Read default config file"
);

diag(`rm $ENV{HOME}/.pt-stalk.conf`);
diag(`cp $ENV{HOME}/.pt-stalk.conf.original $ENV{HOME}/.pt-stalk.conf 2>/dev/null`);

# #############################################################################
# Don't stalk, just collect.
# #############################################################################
diag(`rm $pid_file 2>/dev/null`);
diag(`rm $log_file 2>/dev/null`);
diag(`rm $dest/*   2>/dev/null`);

$retval = system("$trunk/bin/pt-stalk --no-stalk --run-time 2 --dest $dest --prefix nostalk -- --defaults-file=$cnf >$log_file 2>&1");

PerconaTest::wait_for_files("$dest/nostalk-trigger");
$output = `cat $dest/nostalk-trigger`;
like(
   $output,
   qr/Not stalking/,
   "Not stalking, collect triggered"
);

PerconaTest::wait_for_files("$dest/nostalk-hostname");
PerconaTest::wait_for_sh("test \$(grep -c '^TS' $dest/nostalk-df) -ge 2");
chomp($output = `grep -c '^TS' $dest/nostalk-df`);
is(
   $output,
   2,
   "Not stalking, collect ran for --run-time"
);

my $vmstat = `which vmstat 2>/dev/null`;
SKIP: {
   skip "vmstat is not installed", 1 unless $vmstat;
   chomp(my $n=`awk '/[ ]*[0-9]/ { n += 1 } END { print n }' "$dest/nostalk-vmstat"`);
   is(
      $n,
      "2",
      "vmstat ran for --run-time seconds (bug 955860)"
   );
};

is(
   `cat $dest/nostalk-hostname`,
   `hostname`,
   "Not stalking, collect gathered data"
);

ok(
   PerconaTest::not_running("pt-stalk --no-stalk"),
   "Not stalking, pt-stalk is not running"
);

# #############################################################################
# Done.
# #############################################################################
diag(`rm $pid_file 2>/dev/null`);
diag(`rm $log_file 2>/dev/null`);
diag(`rm -rf $dest 2>/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
