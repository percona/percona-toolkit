#!/usr/bin/perl

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
use File::Temp qw(tempfile);

use Daemon;
use PerconaTest;

use constant PTDEVDEBUG => $ENV{PTDEVDEBUG} || 0;

my $cmd      = "$trunk/t/lib/samples/daemonizes.pl";
my $pid_file = "/tmp/pt-daemon-test.pid.$PID";
my $log_file = "/tmp/pt-daemon-test.log.$PID";
sub rm_tmp_files() {
   -f $pid_file && (unlink $pid_file || die "Error removing $pid_file");
   -f $log_file && (unlink $log_file || die "Error removing $log_file");
}

# ############################################################################
# Test that it daemonizes, creates a PID file, and removes that PID file.
# ############################################################################

my $ret_val = system("$cmd 3 --daemonize --pid $pid_file --log $log_file");
die 'Cannot test Daemon.pm because t/daemonizes.pl is not working'
   unless $ret_val == 0;

PerconaTest::wait_for_files($pid_file, $log_file)
   or die "$cmd did not create $pid_file and $log_file";

my ($pid, $output) = PerconaTest::get_cmd_pid("$cmd 3");

like(
   $output,
   qr/$cmd/,
   'Daemonizes'
);

ok(
   -f $pid_file,
   'Creates PID file'
);

$output = slurp_file($pid_file);
chomp($output) if $output;

is(
   $output,
   $pid,
   'PID file has correct PID'
);

SKIP: {
   skip "Previous tests failed", 1 unless $pid;

   # Wait until the process goes away
   PerconaTest::wait_until(sub { !kill(0, $pid) });
   ok(
      ! -f $pid_file,
      'Removes PID file upon exit'
   );
}

# ############################################################################
# Check that STDOUT can be redirected
# ############################################################################
rm_tmp_files();

system("$cmd 0 --daemonize --log $log_file");
PerconaTest::wait_for_files($log_file);

ok(
   -f $log_file,
   'Log file exists'
);

$output = slurp_file($log_file);

like(
   $output,
   qr/STDOUT\nSTDERR\n/,
   'STDOUT and STDERR went to log file'
);

my $log_size = -s $log_file;
PTDEVDEBUG && PerconaTest::_d('log size', $log_size);

# Check that the log file is appended to.
system("$cmd 0 --daemonize --log $log_file");
PerconaTest::wait_until(sub { -s $log_file > $log_size });
$output = slurp_file($log_file);

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

$output = `$cmd 2 --daemonize --pid $pid_file 2>&1`;
like(
   $output,
   qr{PID file $pid_file exists},
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
   skip 'No /proc', 1 unless -d '/proc';
   skip 'No fd in /proc', 1 unless -l "/proc/$PID/0" || -l "/proc/$PID/fd/0";

   system("$cmd 15 --daemonize --pid $pid_file --log $log_file");
   PerconaTest::wait_for_files($pid_file, $log_file)
      or die "$cmd did not create $pid_file and $log_file";
   my $pid = PerconaTest::get_cmd_pid("$cmd 15")
      or die "Cannot get PID of $cmd 15\n" . `ps xww`;
   my $proc_fd_0 = -l "/proc/$pid/0"    ? "/proc/$pid/0"
                 : -l "/proc/$pid/fd/0" ? "/proc/$pid/fd/0"
                 : die "Cannot find fd 0 symlink in /proc/$pid";
   PTDEVDEBUG && PerconaTest::_d('pid_file', $pid_file,
      'pid', $pid, 'proc_fd_0', $proc_fd_0, `ls -l $proc_fd_0`);
   my $stdin = readlink $proc_fd_0;
   is(
      $stdin,
      '/dev/null',
      'Reopens STDIN to /dev/null'
   );

   PerconaTest::kill_program(pid => $pid);

#   SKIP: {
#      skip "-t is not reliable", 1;
#      rm_tmp_files();
#      system("echo foo | $cmd 5 --daemonize --pid $pid_file --log $log_file");
#      PerconaTest::wait_for_files($pid_file, $log_file);
#      chomp($pid = slurp_file($pid_file));
#      $proc_fd_0 = -l "/proc/$pid/0"    ? "/proc/$pid/0"
#               : -l "/proc/$pid/fd/0" ? "/proc/$pid/fd/0"
#               : die "Cannot find fd 0 symlink in /proc/$pid";
#      PTDEVDEBUG && PerconaTest::_d('pid_file', $pid_file,
#         'pid', $pid, 'proc_fd_0', $proc_fd_0, `ls -l $proc_fd_0`);
#      $stdin = readlink $proc_fd_0;
#      like(
#         $stdin,
#         qr/pipe/,
#         'Does not reopen STDIN to /dev/null when piped',
#      );
#      rm_tmp_files();
#   }
}

# ##########################################################################
# Issue 419: Daemon should check wether process with pid obtained from
# pid-file is still running
# ##########################################################################
rm_tmp_files();
system("$cmd 7 --daemonize --pid $pid_file >/dev/null 2>&1");
PerconaTest::wait_for_files($pid_file);
$pid = PerconaTest::get_cmd_pid("$cmd 7")
   or die "Cannot get PID of $cmd 7";
kill 9, $pid;
sleep 0.25;
(undef, $output) = PerconaTest::get_cmd_pid("$cmd 7");
unlike(
   $output,
   qr/daemonize/,
   'Kill 9 daemonizes.pl (issue 419)'
);
ok(
   -f $pid_file,
   'PID file remains after kill 9 (issue 419)'
);

my (undef, $tempfile) = tempfile();

system("$cmd 6 --daemonize --log $log_file --pid $pid_file > $tempfile 2>&1");
PerconaTest::wait_for_files($log_file, $pid_file, $tempfile);
my $new_pid;
($new_pid, $output) = PerconaTest::get_cmd_pid("$cmd 6");

like(
   $output,
   qr/$cmd/,
   'Runs when PID file exists but old process is dead (issue 419)'
);

like(
   slurp_file($tempfile),
   qr/Overwriting PID file $pid_file because PID $pid is not running/,
   'Says that old PID is not running (issue 419)'
);

cmp_ok(
   $pid,
  '!=',
   $new_pid,
   'Overwrites PID file with new PID (issue 419)'
);

PerconaTest::wait_until(sub { !-f $pid_file });
ok(
   !-f $pid_file,
   'Re-used PID file still removed (issue 419)'
);

diag(`rm $tempfile >/dev/null`);
 
# ############################################################################
# Check that it actually checks the running process.
# ############################################################################
rm_tmp_files();
system("$cmd 10 --daemonize --log $log_file --pid $pid_file");
PerconaTest::wait_for_files($pid_file, $log_file);
chomp($pid = slurp_file($pid_file));
$output = `$cmd 1 --daemonize --pid $pid_file 2>&1`;
like(
   $output,
   qr/PID file $pid_file exists and PID $pid is running/,
   'Says that PID is running (issue 419)'
);

PerconaTest::kill_program(pid => $pid);
rm_tmp_files();

# #############################################################################
# Test auto-PID file removal without having to daemonize (for issue 391).
# #############################################################################
my $pid_file2 = "/tmp/pt-daemon-test.pid2.$PID";
{
   my $d2 = Daemon->new(
      pid_file => $pid_file2,
   );
   $d2->run();
   ok(
      -f $pid_file2,
      'PID file for non-daemon exists'
   );
}
# Since $d2 was locally scoped, it should have been destoryed by now.
# This should have caused the PID file to be automatically removed.
ok(
   !-f $pid_file2,
   'PID file auto-removed for non-daemon'
);

# We should still die if the PID file already exists,
# even if we're not a daemon.
{
   diag(`touch $pid_file2`);
   eval {
      my $d2 = Daemon->new(
         pid_file => $pid_file2,
      );
      $d2->run();
   };
   like(
      $EVAL_ERROR,
      qr/PID file $pid_file2 exists/,
      'Dies if PID file already exists for non-daemon'
   );

   unlink $pid_file2 if -f $pid_file2;
}

# #############################################################################
# Done.
# #############################################################################
rm_tmp_files();
done_testing;
