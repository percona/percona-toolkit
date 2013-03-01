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
use IO::File;

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

local $SIG{CHLD} = 'IGNORE';
my $pid = fork();
die "Cannot fork: $OS_ERROR" unless defined $pid;
if ( !$pid ) {
   exec { $cmd } $cmd, qw(--lines 2), $filename;
   exit 1;
}

PerconaTest::wait_until(sub { -p $fifo });
my @fifo;
while (kill 0, $pid) {
   if ( -e $fifo ) {
       eval {
          local $SIG{ALRM} = sub { die "read timeout" };
          alarm 3;
          my $contents = slurp_file($fifo);
          push @fifo,  $contents;
          alarm 0;
       };
       if (my $e = $@) {
          die $e unless $e =~ /\Aread timeout\z/;
       }
   }
}
waitpid($pid, 0);

is_deeply(
   \@fifo,
   [
      "1\n2\n",
      "3\n4\n",
      "5\n6\n",
      "7\n8\n",
      "9\n",
   ],
   "--lines=2 with 9 lines works as expected"
);

$pid = fork();
die "Cannot fork: $OS_ERROR" unless defined $pid;
if ( !$pid ) {
   exec { $cmd } $cmd, qw(--lines 15), $filename;
   exit 1;
}
PerconaTest::wait_until(sub { -p $fifo });

@fifo = ();
while (kill 0, $pid) {
   if ( -e $fifo ) {
       eval {
          local $SIG{ALRM} = sub { die "read timeout" };
          alarm 3;
          my $contents = slurp_file($fifo);
          push @fifo,  $contents;
          alarm 0;
       };
       if (my $e = $@) {
          die $e unless $e =~ /\Aread timeout\z/;
       }
   }
}
waitpid($pid, 0);

is_deeply(
   \@fifo,
   [
      "1\n2\n3\n4\n5\n6\n7\n8\n9\n",
   ],
   "--lines=15 with 9 lines works as expected"
);

close $fh or die "Cannot close $filename: $OS_ERROR";

system("($cmd --lines 10000 $trunk/bin/pt-fifo-split > /dev/null 2>&1 < /dev/null)&");
PerconaTest::wait_until(sub { -p $fifo });

my $contents  = slurp_file($fifo) if -e $fifo;
my $contents2 = load_file('bin/pt-fifo-split');

is($contents, $contents2, 'I read the file');

system("($cmd $trunk/t/pt-fifo-split/samples/file_with_lines --offset 2 > /dev/null 2>&1 < /dev/null)&");
PerconaTest::wait_until(sub { -p $fifo });

$contents = slurp_file($fifo) if -e $fifo;

is($contents, <<EOF
     2	hi
     3	there
     4	b
     5	c
     6	d
EOF
, 'Offset works');

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
