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
use DSNParser;
use Sandbox;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 14;
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

$output = `ps x | grep -v grep | grep 'pt-stalk pt-stalk --iterations 1 --dest $dest'`;
is(
   $output,
   "",
   "pt-stalk is not running"
);

# #############################################################################
# Done.
# #############################################################################
diag(`rm $pid_file 2>/dev/null`);
diag(`rm $log_file 2>/dev/null`);
diag(`rm -rf $dest 2>/dev/null`);
exit;
