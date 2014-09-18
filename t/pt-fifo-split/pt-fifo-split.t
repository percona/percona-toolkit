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
use File::Temp qw(tempfile);
use Data::Dumper;
use Time::HiRes qw(sleep);

use PerconaTest;
require "$trunk/bin/pt-fifo-split";

my $fifo = '/tmp/pt-fifo-split';
unlink($fifo) if $fifo;

my $cmd = "$trunk/bin/pt-fifo-split";

my $output = `$cmd --help`;
like($output, qr/Options and values/, 'It lives');

my ($fh, $filename) = tempfile("pt-fifo-split-data.XXXXXXXXX", OPEN => 1, TMPDIR => 1, UNLINK => 1);
$fh->autoflush(1);
print { $fh } "$_\n" for 1..9;
close $fh;

# WARNING: This can "deadlock" if not done correctly.  First, for Perl open():
# "When you open a fifo, the program will block until there's something on
# the other end."  So pt-fifo-split needs to mkfifo and open() it first,
# then we open it.  That's ok, but the problem is: after we read everything,
# pt-fifo-split will close, rm, mkfifo, and open() it again.  That can take
# a few microseconds longer than the test closing and trying to read the
# fifo again.  In fact, the test can close, -p $fifo, and open() before
# pt-fifo-split has done rm (unlink).  When this happens, the test holds
# open the fifo it just read, then pt-fifo-split creates a new fifo and
# open()s it and blocks because there's no program on the other end--
# because the test is reading a phantom fifo.  Rather make the tool sleep
# some arbitrary time before re-open()ing the fifo, we check for a new
# file inode which ensures the fifo is new.
sub read_fifo {
   my ($n_reads) = @_;
   my $last_inode = 0;
   my @data;

   # This test still freezes on some centos systems, 
   # so we're going to bluntly sleep for a few secs to avoid deadlock 
   # TODO: figure out if there is a proper way to do this. 
   sleep(3);

   for (1..$n_reads) {
      PerconaTest::wait_until(sub {
         my $inode;
         (undef, $inode) = stat($fifo) if -p $fifo;
         if ( $inode && $inode != $last_inode ) {
            $last_inode = $inode;
            return 1;
         }
         return;
      });
      open my $read_fifo_fh, '<', $fifo
         or die "Cannot open $fifo: $OS_ERROR";
      my $data = '';
      while ( <$read_fifo_fh> ) {
         $data .= $_;
      }
      close $read_fifo_fh;
      push @data, $data;
   }
   return \@data;
}

local $SIG{CHLD} = 'IGNORE';
my $pid = fork();
die "Cannot fork: $OS_ERROR" unless defined $pid;
if ( !$pid ) {
   exec { $cmd } $cmd, qw(--lines 2), $filename;
}

my $data = read_fifo(5);

waitpid($pid, 0);

is_deeply(
   $data,
   [
      "1\n2\n",
      "3\n4\n",
      "5\n6\n",
      "7\n8\n",
      "9\n",
   ],
   "--lines=2 with 9 lines works as expected"
) or diag(Dumper($data));

$pid = fork();
die "Cannot fork: $OS_ERROR" unless defined $pid;
if ( !$pid ) {
   exec { $cmd } $cmd, qw(--lines 15), $filename;
}

$data = read_fifo(1);

waitpid($pid, 0);

is_deeply(
   $data,
   [ "1\n2\n3\n4\n5\n6\n7\n8\n9\n" ],
   "--lines=15 with 9 lines works as expected"
) or diag(Dumper($data));

system("($cmd --lines 10000 $trunk/bin/pt-fifo-split > /dev/null 2>&1 < /dev/null)&");

$data = read_fifo(1);

my $contents2 = load_file('bin/pt-fifo-split');

is_deeply(
   $data,
   [ $contents2 ],
   'I read the file'
);

system("($cmd $trunk/t/pt-fifo-split/samples/file_with_lines --offset 2 > /dev/null 2>&1 < /dev/null)&");

$data = read_fifo(1);

is_deeply(
   $data,
   [
<<EOF
     2	hi
     3	there
     4	b
     5	c
     6	d
EOF
   ],
   'Offset works'
);

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
my $pid_file = "/tmp/pt-fifo-split.pid.$PID";
diag(`touch $pid_file`);

$output = `$cmd --pid $pid_file 2>&1`;
like(
   $output,
   qr{PID file $pid_file already exists},
   'Dies if PID file already exists (issue 391)'
);

unlink $pid_file if -f $pid_file;

# #############################################################################
# Done.
# #############################################################################
done_testing;
