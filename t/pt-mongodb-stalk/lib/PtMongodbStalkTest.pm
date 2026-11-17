# Shared helpers for the pt-mongodb-stalk tests.
#
# The tests that do not need a MongoDB server call use_fake_commands(), which
# puts the fake commands in t/pt-mongodb-stalk/samples/bin first in PATH.  The
# fakes act out mongosh, mongostat, mongotop and the system commands, and log
# how they were called; see the comments in each of them.
package PtMongodbStalkTest;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Exporter qw(import);
use File::Path qw(make_path);
use File::Temp qw(tempdir);

use PerconaTest;

our @EXPORT = qw(
   $tool $tmpdir $fakebin $password @common_args
   use_fake_commands run_capture run_capture_timeout run_capture_until
   prefixes_in collect_with
);

our $tool     = "$trunk/bin/pt-mongodb-stalk";
our $fakebin  = "$trunk/t/pt-mongodb-stalk/samples/bin";
our $tmpdir   = tempdir("pt-mongodb-stalk.XXXXXX", TMPDIR => 1, CLEANUP => 1);
our $password = 'S3cretPw';

# A short --no-stalk collection with credentials, against the fake commands.
our @common_args = (
   "--host", "localhost",
   "--port", "27017",
   "--user", "admin",
   "--password", $password,
   "--authenticationDatabase", "admin",
   "--no-stalk",
   "--run-time", "1",
   "--sleep-collect", "1",
   "--disk-pct-free", "1",
   "--disk-bytes-free", "1",
);

my $run_no = 0;

# Put the fake commands first in PATH and set the files they log to.  TMPDIR
# is a directory of its own, so the tests can check that the tool removes its
# temporary directory.
sub use_fake_commands {
   make_path("$tmpdir/tmp");
   $ENV{PATH}                   = "$fakebin:$ENV{PATH}";
   $ENV{TMPDIR}                 = "$tmpdir/tmp";
   $ENV{MONGOSH_LOG}            = "$tmpdir/mongosh.log";
   $ENV{MONGOSH_ARGS_LOG}       = "$tmpdir/mongosh-args.log";
   $ENV{MONGO_TOOLS_LOG}        = "$tmpdir/mongo-tools.log";
   $ENV{MONGO_TOOLS_CONFIG_LOG} = "$tmpdir/mongo-tools-config.log";
   $ENV{MAIL_LOG}               = "$tmpdir/mail.log";
   $ENV{PTDEBUG}                = "";
   return;
}

# Run a command; return its exit status and its stdout and stderr.
sub run_capture {
   my (@cmd) = @_;
   my ($pid, $out) = _start(@cmd);
   waitpid($pid, 0);
   my $status = $CHILD_ERROR >> 8;
   return ($status, slurp_file($out));
}

# Like run_capture, but send SIGTERM to the command after $timeout seconds,
# for runs that only stop on a signal (e.g. a trigger that never matches).
# Return its stdout and stderr.
sub run_capture_timeout {
   my ($timeout, @cmd) = @_;
   my ($pid, $out) = _start(@cmd);
   my $waited = 0;
   while ( waitpid($pid, 1) == 0 ) {  # 1 = WNOHANG
      if ( $waited++ == $timeout * 10 ) {
         kill 'TERM', $pid;
      }
      select(undef, undef, undef, 0.1);
   }
   return slurp_file($out);
}

# Run a command until its output matches $pattern, then send it SIGTERM, or
# until it exits, or for at most $timeout seconds.  For runs that only stop on
# a signal, without waiting longer than needed: mongosh can take seconds to
# start on a busy host.  Return its stdout and stderr.
sub run_capture_until {
   my ($pattern, $timeout, @cmd) = @_;
   my ($pid, $out) = _start(@cmd);
   my $waited = 0;
   my $killed = 0;
   while ( waitpid($pid, 1) == 0 ) {  # 1 = WNOHANG
      if ( !$killed
           && ($waited++ >= $timeout * 10 || (-s $out && slurp_file($out) =~ $pattern)) ) {
         kill 'TERM', $pid;
         $killed = 1;
      }
      select(undef, undef, undef, 0.1);
   }
   return slurp_file($out);
}

sub _start {
   my (@cmd) = @_;
   $run_no++;
   my $out = "$tmpdir/run-$run_no.out";
   my $pid = fork();
   die "Cannot fork: $OS_ERROR" unless defined $pid;
   if ( !$pid ) {
      open STDOUT, ">", $out or die "Cannot redirect stdout: $OS_ERROR";
      open STDERR, ">&", \*STDOUT or die "Cannot redirect stderr: $OS_ERROR";
      exec @cmd;
      die "Cannot exec $cmd[0]: $OS_ERROR";
   }
   return ($pid, $out);
}

# The collection prefixes in a directory: every file is <prefix>-<name>.
sub prefixes_in {
   my ($dir) = @_;
   my %prefixes;
   for my $file ( glob("$dir/*-*") ) {
      my ($prefix) = $file =~ m{/([^/]+?)-[^/]+$};
      $prefixes{$prefix}++ if $prefix;
   }
   return sort keys %prefixes;
}

# Run one short collection with @common_args plus @args, in a directory of its
# own.  Return the exit status, the output, and the path of the collection's
# files without the -<name> suffix.
my $collect_no = 0;
sub collect_with {
   my (@args) = @_;
   my $dir = "$tmpdir/collect-" . ++$collect_no;
   my ($status, $output) = run_capture(
      "bash", $tool, @common_args,
      "--iterations", "1", "--sleep", "0",
      "--dest", $dir, "--pid", "$tmpdir/collect-$collect_no.pid",
      @args,
   );
   my ($trigger) = glob("$dir/*-trigger");
   (my $prefix = $trigger || "$dir/none") =~ s/-trigger$//;
   return ($status, $output, $prefix);
}

1;
