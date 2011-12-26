#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 22;
use Time::HiRes qw(sleep);
use Daemon;
use OptionParser;
use PerconaTest;

my $o = OptionParser->new(file => "$trunk/t/lib/samples/daemonizes.pl");
my $d = Daemon->new(o=>$o);

my $pid_file = '/tmp/daemonizes.pl.pid';
my $log_file = '/tmp/daemonizes.output'; 
sub rm_tmp_files() {
   `rm $pid_file $log_file >/dev/null 2>&1`
}

# ############################################################################
# Test that it daemonizes, creates a PID file, and removes that PID file.
# ############################################################################
rm_tmp_files();

my $cmd     = "$trunk/t/lib/samples/daemonizes.pl";
my $ret_val = system("$cmd 2 --daemonize --pid $pid_file");
die 'Cannot test Daemon.pm because t/daemonizes.pl is not working'
   unless $ret_val == 0;

PerconaTest::wait_for_files($pid_file);

my $output = `ps wx | grep '$cmd 2' | grep -v grep`;
like($output, qr/$cmd/, 'Daemonizes');
ok(-f $pid_file, 'Creates PID file');

my ($pid) = $output =~ /\s*(\d+)\s+/;
$output = `cat $pid_file`;
is($output, $pid, 'PID file has correct PID');

sleep 2;
ok(! -f $pid_file, 'Removes PID file upon exit');

# ############################################################################
# Check that STDOUT can be redirected
# ############################################################################
rm_tmp_files();

system("$cmd 2 --daemonize --log $log_file");
PerconaTest::wait_for_files($log_file);
ok(-f $log_file, 'Log file exists');

sleep 2;
$output = `cat $log_file`;
like($output, qr/STDOUT\nSTDERR\n/, 'STDOUT and STDERR went to log file');

# Check that the log file is appended to.
system("$cmd 0 --daemonize --log $log_file");
PerconaTest::wait_for_files($log_file);
$output = `cat $log_file`;
like(
   $output,
   qr/STDOUT\nSTDERR\nSTDOUT\nSTDERR\n/,
   'Appends to log file'
);

# ##########################################################################
# Issue 383: mk-deadlock-logger should die if --pid file specified exists
# ##########################################################################
rm_tmp_files();
diag(`touch $pid_file`);
ok(
   -f  $pid_file,
   'PID file already exists'
);

$output = `MKDEBUG=1 $cmd 0 --daemonize --pid $pid_file 2>&1`;
like(
   $output,
   qr{The PID file $pid_file already exists},
   'Dies if PID file already exists'
);

$output = `ps wx | grep '$cmd 0' | grep -v grep`;
unlike(
   $output,
   qr/$cmd/,
   'Does not daemonizes'
);

# ##########################################################################
# Issue 417: --daemonize doesn't let me log out of terminal cleanly
# ##########################################################################
rm_tmp_files();
SKIP: {
   skip 'No /proc', 2 unless -d '/proc';
   skip 'No fd in /proc', 2 unless -l "/proc/$PID/0" || -l "/proc/$PID/fd/0";

   system("$cmd 1 --daemonize --pid $pid_file --log $log_file");
   PerconaTest::wait_for_files($pid_file);
   chomp($pid = `cat $pid_file`);
   my $proc_fd_0 = -l "/proc/$pid/0"    ? "/proc/$pid/0"
                 : -l "/proc/$pid/fd/0" ? "/proc/$pid/fd/0"
                 : die "Cannot find fd 0 symlink in /proc/$pid";
   my $stdin = readlink $proc_fd_0;
   is(
      $stdin,
      '/dev/null',
      'Reopens STDIN to /dev/null if not piped',
   );

   sleep 1;
   system("echo foo | $cmd 1 --daemonize --pid $pid_file --log $log_file");
   PerconaTest::wait_for_files($pid_file, $log_file);
   chomp($pid = `cat $pid_file`);
   $proc_fd_0 = -l "/proc/$pid/0"    ? "/proc/$pid/0"
              : -l "/proc/$pid/fd/0" ? "/proc/$pid/fd/0"
              : die "Cannot find fd 0 symlink in /proc/$pid";
   $stdin = readlink $proc_fd_0;
   like(
      $stdin,
      qr/pipe/,
      'Does not reopen STDIN to /dev/null when piped',
   );
   sleep 1;
};

# ##########################################################################
# Issue 419: Daemon should check wether process with pid obtained from
# pid-file is still running
# ##########################################################################
rm_tmp_files();
system("$cmd 5 --daemonize --pid $pid_file 2>&1");
PerconaTest::wait_for_files($pid_file);
chomp($pid = `cat $pid_file`);
kill 9, $pid;
sleep 0.25;
$output = `ps wx | grep '^[ ]*$pid' | grep -v grep`;
unlike(
   $output,
   qr/daemonize/,
   'Kill 9 daemonizes.pl (issue 419)'
);
ok(
   -f $pid_file,
   'PID file remains after kill 9 (issue 419)'
);

system("$cmd 1 --daemonize --log $log_file --pid $pid_file 2>/tmp/pre-daemonizes");
PerconaTest::wait_for_files($log_file);
$output = `ps wx | grep '$cmd 1' | grep -v grep`;
chomp(my $new_pid = `cat $pid_file`);
sleep 1;
like(
   $output,
   qr/$cmd/,
   'Runs when PID file exists but old process is dead (issue 419)'
);
like(
   `cat /tmp/pre-daemonizes`,
   qr/$pid, is not running/,
   'Says that old PID is not running (issue 419)'
);
ok(
   $pid != $new_pid,
   'Overwrites PID file with new PID (issue 419)'
);
ok(
   !-f $pid_file,
   'Re-used PID file still removed (issue 419)'
);
diag(`rm -rf /tmp/pre-daemonizes`);
 
# ############################################################################
# Check that it actually checks the running process.
# ############################################################################
rm_tmp_files();
system("$cmd 1 --daemonize --log $log_file --pid $pid_file");
PerconaTest::wait_for_files($pid_file, $log_file);
chomp($pid = `cat $pid_file`);
$output = `$cmd 0 --daemonize --pid $pid_file 2>&1`;
like(
   $output,
   qr/$pid, is running/,
   'Says that PID is running (issue 419)'
);

sleep 1;
rm_tmp_files();

# #############################################################################
# Test auto-PID file removal without having to daemonize (for issue 391).
# #############################################################################
{
   @ARGV = qw(--pid /tmp/d2.pid);
   $o->get_specs("$trunk/t/lib/samples/daemonizes.pl");
   $o->get_opts();
   my $d2 = Daemon->new(o=>$o);
   $d2->make_PID_file();
   ok(
      -f '/tmp/d2.pid',
      'PID file for non-daemon exists'
   );
}
# Since $d2 was locally scoped, it should have been destoryed by now.
# This should have caused the PID file to be automatically removed.
ok(
   !-f '/tmpo/d2.pid',
   'PID file auto-removed for non-daemon'
);

# We should still die if the PID file already exists,
# even if we're not a daemon.
{
   `touch /tmp/d2.pid`;
   @ARGV = qw(--pid /tmp/d2.pid);
   $o->get_opts();
   eval {
      my $d2 = Daemon->new(o=>$o);  # should die here actually
      $d2->make_PID_file();
   };
   like(
      $EVAL_ERROR,
      qr{PID file /tmp/d2.pid already exists},
      'Dies if PID file already exists for non-daemon'
   );

   `rm -rf /tmp/d2.pid`;
}

# #############################################################################
# Done.
# #############################################################################
rm_tmp_files();
exit;
