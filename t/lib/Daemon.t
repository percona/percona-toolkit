#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 23;

use Daemon;
use OptionParser;
use MaatkitTest;

my $o = new OptionParser(file => "$trunk/t/lib/samples/daemonizes.pl");
my $d = new Daemon(o=>$o);

my $pid_file = '/tmp/daemonizes.pl.pid';
my $log_file = '/tmp/daemonizes.output';

isa_ok($d, 'Daemon');

my $cmd     = "$trunk/t/lib/samples/daemonizes.pl";
my $ret_val = system("$cmd 2 --daemonize --pid $pid_file");
SKIP: {
   skip 'Cannot test Daemon.pm because t/daemonizes.pl is not working',
      19 unless $ret_val == 0;

   my $output = `ps wx | grep '$cmd 2' | grep -v grep`;
   like($output, qr/$cmd/, 'Daemonizes');
   ok(-f $pid_file, 'Creates PID file');

   my ($pid) = $output =~ /\s*(\d+)\s+/;
   $output = `cat $pid_file`;
   is($output, $pid, 'PID file has correct PID');

   sleep 2;
   ok(! -f $pid_file, 'Removes PID file upon exit');

   # Check that STDOUT can be redirected
   system("$cmd 2 --daemonize --log /tmp/mk-daemon.log");
   ok(-f '/tmp/mk-daemon.log', 'Log file exists');

   sleep 2;
   $output = `cat /tmp/mk-daemon.log`;
   like($output, qr/STDOUT\nSTDERR\n/, 'STDOUT and STDERR went to log file');

   # Check that the log file is appended to.
   system("$cmd 0 --daemonize --log /tmp/mk-daemon.log");
   $output = `cat /tmp/mk-daemon.log`;
   like(
      $output,
      qr/STDOUT\nSTDERR\nSTDOUT\nSTDERR\n/,
      'Appends to log file'
   );

   `rm -f /tmp/mk-daemon.log`;

   # ##########################################################################
   # Issue 383: mk-deadlock-logger should die if --pid file specified exists
   # ##########################################################################
   diag(`touch $pid_file`);
   ok(
      -f  $pid_file,
      'PID file already exists'
   );
   
   $output = `MKDEBUG=1 $cmd 0 --daemonize --pid $pid_file 2>&1`;
   like(
      $output,
      qr{The PID file /tmp/daemonizes\.pl\.pid already exists},
      'Dies if PID file already exists'
   );

    $output = `ps wx | grep '$cmd 0' | grep -v grep`;
    unlike(
      $output,
      qr/$cmd/,
      'Does not daemonizes'
   );
   
   diag(`rm -rf $pid_file`);  

   # ##########################################################################
   # Issue 417: --daemonize doesn't let me log out of terminal cleanly
   # ##########################################################################
   SKIP: {
      skip 'No /proc', 2 unless -d '/proc';
      skip 'No fd in /proc', 2 unless -l "/proc/$PID/0" || -l "/proc/$PID/fd/0";

      system("$cmd 1 --daemonize --pid $pid_file --log $log_file");
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

   };

   # ##########################################################################
   # Issue 419: Daemon should check wether process with pid obtained from
   # pid-file is still running
   # ##########################################################################
   system("$cmd 5 --daemonize --pid $pid_file 2>&1");
   chomp($pid = `cat $pid_file`);
   kill 9, $pid;
   $output = `ps wax | grep $pid | grep -v grep`;
   unlike(
      $output,
      qr/daemonize/,
      'Kill 9 daemonizes.pl (issue 419)'
   );
   ok(
      -f $pid_file,
      'PID file remains after kill 9 (issue 419)'
   );

   diag(`rm -rf $log_file`);
   system("$cmd 1 --daemonize --log $log_file --pid $pid_file 2>/tmp/pre-daemonizes");
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

   # Check that it actually checks the running process.
   system("$cmd 1 --daemonize --log $log_file --pid $pid_file");
   chomp($pid = `cat $pid_file`);
   $output = `$cmd 0 --daemonize --pid $pid_file 2>&1`;
   like(
      $output,
      qr/$pid, is running/,
      'Says that PID is running (issue 419)'
   );

   sleep 1;

   # Make sure PID file is gone to make subsequent tests happy.
   diag(`rm -rf $pid_file`);
   diag(`rm -rf $log_file`);
   diag(`rm -rf /tmp/pre-daemonizes`);
}

# #############################################################################
# Test auto-PID file removal without having to daemonize (for issue 391).
# #############################################################################
{
   @ARGV = qw(--pid /tmp/d2.pid);
   $o->get_specs("$trunk/t/lib/samples/daemonizes.pl");
   $o->get_opts();
   my $d2 = new Daemon(o=>$o);
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
      my $d2 = new Daemon(o=>$o);  # should die here actually
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
diag(`rm -rf /tmp/daemonizes.*`);
exit;
