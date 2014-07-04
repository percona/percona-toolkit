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
my $int_file = "/tmp/pt-stalk-after-interval-sleep";
my $pid;

sub cleanup {
   diag(`rm $pid_file $log_file $int_file 2>/dev/null`);
   diag(`rm -rf $dest 2>/dev/null`);
}

sub wait_n_cycles {
   my ($n) = @_;
   PerconaTest::wait_until(
      sub {
         return 0 unless -f "$dest/after_interval_sleep";
         my $n_cycles = `wc -l "$dest/after_interval_sleep"  | awk '{print \$1}'`;
         $n_cycles ||= '';
         chomp($n_cycles);
         return ($n_cycles || 0) >= $n; 
      },
      1.5,
      15
   );
}

# ###########################################################################
# Test that it won't run if can't connect to MySQL.
# ###########################################################################

my $retval = system("$trunk/bin/pt-stalk -- --no-defaults --protocol socket --socket /dev/null  >$log_file 2>&1");
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

cleanup();

# As of v2.1.9 when --verbose was added, non-matching checks are not
# printed by default.  So we use the --plugin to tell us when the tool
# has completed a cycle.
$retval = system("$trunk/bin/pt-stalk --daemonize --pid $pid_file --log $log_file --dest $dest --plugin $trunk/t/pt-stalk/samples/plugin002.sh -- --defaults-file=$cnf");

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

chomp($pid = `cat $pid_file 2>/dev/null`);
$retval = system("kill -0 $pid");
is(
   $retval >> 0,
   0,
   "pt-stalk is running"
);

wait_n_cycles(2);
PerconaTest::kill_program(pid_file => $pid_file);

$output = `cat $log_file 2>/dev/null`;
unlike(
   $output,
   qr/Check results: status\(Threads_running\)=\d+, matched=no, cycles_true=0/,
   "Non-matching results not logged because --verbose=2"
) or diag(`cat $log_file 2>/dev/null`, `cat $dest/*-output 2>/dev/null`);

PerconaTest::wait_until(sub { !-f $pid_file });

ok(
   ! -f $pid_file,
   "Removes PID file"
);

$output = `cat $log_file 2>/dev/null`;
like(
   $output,
   qr/Caught signal, exiting/,
   "Caught signal logged"
) or diag(`cat $log_file 2>/dev/null`, `cat $dest/*-output 2>/dev/null`);

# #############################################################################
# --verbose 3 (non-matching results)
# #############################################################################

cleanup();

$retval = system("$trunk/bin/pt-stalk --daemonize --pid $pid_file --log $log_file --variable Threads_running --dest $dest --verbose 3 -- --defaults-file=$cnf");

PerconaTest::wait_for_files($pid_file, $log_file);
PerconaTest::wait_for_sh("grep -q 'Check results' $log_file >/dev/null");
PerconaTest::kill_program(pid_file => $pid_file);

$output = `cat $log_file 2>/dev/null`;
like(
   $output,
   qr/Check results: status\(Threads_running\)=\d+, matched=no, cycles_true=0/,
   "Matching results logged with --verbose 3"
) or diag(`cat $dest/*-output 2>/dev/null`);

# #############################################################################
# --verbose 1 (just errors and warnings)
# #############################################################################

cleanup();

$retval = system("$trunk/bin/pt-stalk --daemonize --pid $pid_file --log $log_file --dest $dest --verbose 1 --plugin $trunk/t/pt-stalk/samples/plugin002.sh -- --defaults-file=$cnf");

PerconaTest::wait_for_files($pid_file, $log_file);
wait_n_cycles(2);
PerconaTest::kill_program(pid_file => $pid_file);

$output = `cat $log_file 2>/dev/null`;

like(
   $output,
   qr/Caught signal, exiting/,
   "Warning logged (--verbose 1)"
);

unlike(
   $output,
   qr/Start|Collect|Check/i,
   "No run info log (--verbose 1)"
);

# ###########################################################################
# Test collect.
# ###########################################################################

cleanup();

# We'll have to watch Uptime since it's the only status var that's going
# to be predictable.
my (undef, $uptime) = $dbh->selectrow_array("SHOW STATUS LIKE 'Uptime'");
my $threshold = $uptime + 2;

$retval = system("$trunk/bin/pt-stalk --iterations 1 --dest $dest --variable Uptime --threshold $threshold --cycles 2 --run-time 2 --pid $pid_file -- --defaults-file=$cnf >$log_file 2>&1");

PerconaTest::wait_until(sub { !-f $pid_file });

$output = `cat $dest/*-trigger 2>/dev/null`;
like(
   $output,
   qr/Check results: status\(Uptime\)=\d+, matched=yes, cycles_true=2/,
   "Collect triggered"
)
or diag(
   'output',    $output,
   'log file',  `cat $log_file 2>/dev/null`,
   'collector', `cat $dest/*-output 2>/dev/null`,
   'dest',      `ls -l $dest/ 2>/dev/null`,
   'df',        `cat $dest/*-df 2>/dev/null`,
);

# There is some nondeterminism here. Sometimes it'll run for 2 samples because
# the samples may not be precisely 1 second apart.
chomp($output = `cat $dest/*-df 2>/dev/null | grep -c '^TS'`);
ok(
   $output >= 1 && $output <= 3,
   "Collect ran for --run-time"
)
or diag(
   'output',    $output,
   'log file',  `cat $log_file 2>/dev/null`,
   'collector', `cat $dest/*-output 2>/dev/null`,
   'dest',      `ls -l $dest/ 2>/dev/null`,
   'df',        `cat $dest/*-df 2>/dev/null`,
);

ok(
   PerconaTest::not_running("pt-stalk --iterations 1"),
   "pt-stalk is not running"
);

$output = `cat $dest/*-trigger 2>/dev/null`;
like(
   $output,
   qr/pt-stalk ran with --function=status --variable=Uptime --threshold=$threshold/,
   "Trigger file logs how pt-stalk was ran"
);

chomp($output = `cat $log_file 2>/dev/null | grep 'Collect [0-9] PID'`);
like(
   $output,
   qr/Collect 1 PID \d+/,
   "Collector PID logged"
)
or diag(
   'output',    $output,
   'log file',  `cat $log_file 2>/dev/null`,
   'collector', `cat $dest/*-output 2>/dev/null`,
);

# ###########################################################################
# Triggered but --no-collect.
# ###########################################################################

cleanup();

(undef, $uptime) = $dbh->selectrow_array("SHOW STATUS LIKE 'Uptime'");
$threshold = $uptime + 2;

$retval = system("$trunk/bin/pt-stalk --no-collect --iterations 1 --dest $dest  --variable Uptime --threshold $threshold --cycles 1 --run-time 1 --pid $pid_file -- --defaults-file=$cnf >$log_file 2>&1");

PerconaTest::wait_until(sub { !-f $pid_file });

$output = `cat $log_file 2>/dev/null`;
like(
   $output,
   qr/Collect 1 triggered/,
   "Collect triggered"
);

ok(
   ! -f "$dest/*",
   "No files collected"
) or diag(`ls -l $dest/ 2>/dev/null`);

ok(
   PerconaTest::not_running("pt-stalk --no-collect"),
   "pt-stalk is not running"
);

# #############################################################################
# --config
# #############################################################################

cleanup();

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

$output = `cat $log_file 2>/dev/null`;
like(
   $output,
   qr/Check results: status\(Aborted_connects\)=|variable=Aborted_connects/,
   "Read default config file"
);

diag(`rm $ENV{HOME}/.pt-stalk.conf`);
diag(`cp $ENV{HOME}/.pt-stalk.conf.original $ENV{HOME}/.pt-stalk.conf 2>/dev/null`);

# #############################################################################
# Don't stalk, just collect.
# #############################################################################

cleanup();

# As of 2.2, --no-stalk means just that: don't stalk, just collect, so
# we have to specify --iterations=1 else the tool will continue to run,
# whereas in 2.1 --no-stalk implied/forced "collect once and exit".

$retval = system("$trunk/bin/pt-stalk --no-stalk --run-time 2 --dest $dest --prefix nostalk --pid $pid_file --iterations 1 -- --defaults-file=$cnf >$log_file 2>&1");

PerconaTest::wait_until(sub { !-f $pid_file });

$output = `cat $dest/nostalk-trigger 2>/dev/null`;
like(
   $output,
   qr/Not stalking/,
   "Not stalking, collect triggered"
)
or diag(
   'dest',      `ls -l $dest/ 2>/dev/null`,
   'log_file',  `cat $log_file 2>/dev/null`,
   'collector', `cat $dest/*-output 2>/dev/null`,
);

chomp($output = `grep -c '^TS' $dest/nostalk-df 2>/dev/null`);
is(
   $output,
   2,
   "Not stalking, collect ran for --run-time"
)
or diag(
   'dest',      `ls -l $dest/ 2>/dev/null`,
   'log_file',  `cat $log_file 2>/dev/null`,
   'collector', `cat $dest/*-output 2>/dev/null`,
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
   `cat $dest/nostalk-hostname 2>/dev/null`,
   `hostname`,
   "Not stalking, collect gathered data"
)
or diag(
   'dest',      `ls -l $dest/ 2>/dev/null`,
   'log_file',  `cat $log_file 2>/dev/null`,
   'collector', `cat $dest/*-output 2>/dev/null`,
);

ok(
   PerconaTest::not_running("pt-stalk --no-stalk"),
   "Not stalking, pt-stalk is not running"
)
or diag(
   'dest',      `ls -l $dest/ 2>/dev/null`,
   'log_file',  `cat $log_file 2>/dev/null`,
   'collector', `cat $dest/*-output 2>/dev/null`,
);

# ############################################################################
# bad "find" usage in purge_samples gives 
# https://bugs.launchpad.net/percona-toolkit/+bug/942114
# ############################################################################

use File::Temp qw( tempdir );

my $tempdir = tempdir( CLEANUP => 1 );

my $script = <<"EOT";
. $trunk/bin/pt-stalk
purge_samples $tempdir 10000 2>&1
EOT

$output = `$script`;

unlike(
   $output,
   qr/\Qfind: warning: you have specified the -depth option/,
   "Bug 942114: no bad find usage"
);


# ###########################################################################
# Test that it handles floating point values 
# ###########################################################################

cleanup();

system("$trunk/bin/pt-stalk --daemonize  --variable=PI --dest $dest  --no-collect --log $log_file --iterations=1  --run-time=2  --cycles=2  --sleep=1 --function $trunk/t/pt-stalk/samples/plugin003.sh --threshold 3.1415  --pid $pid_file --defaults-file=$cnf >$log_file 2>&1");


sleep 5;
PerconaTest::kill_program(pid_file => $pid_file);

$output = `cat $log_file 2>/dev/null`;
like(
   $output,
   qr/matched=yes/,
   "Accepts floating point values as treshold variable"
);


# #############################################################################
# Done.
# #############################################################################
cleanup();
diag(`rm -rf $dest 2>/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
