#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use File::Temp qw(tempfile);
use Test::More;

if ( !$ENV{SLOW_TESTS} ) {
   plan skip_all => "pt-fifo-split/pt-fifo-split. is a top 5 slowest file; set SLOW_TESTS=1 to enable it.";
}

use PerconaTest;
require "$trunk/bin/pt-fifo-split";

my $fifo = '/tmp/pt-fifo-split';
unlink($fifo);

my $cmd = "$trunk/bin/pt-fifo-split";

my $output = `$cmd --help`;
like($output, qr/Options and values/, 'It lives');

require IO::File;
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

PerconaTest::wait_for_files($fifo);
my @fifo;
while (kill 0, $pid) {
   push @fifo, slurp_file($fifo) if -e $fifo;
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
PerconaTest::wait_for_files($fifo);

@fifo = ();
while (kill 0, $pid) {
   push @fifo, slurp_file($fifo) if -e $fifo;
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
PerconaTest::wait_for_files($fifo);

my $contents  = slurp_file($fifo);
my $contents2 = load_file('bin/pt-fifo-split');

is($contents, $contents2, 'I read the file');

system("($cmd $trunk/t/pt-fifo-split/samples/file_with_lines --offset 2 > /dev/null 2>&1 < /dev/null)&");
PerconaTest::wait_for_files($fifo);

$contents = slurp_file($fifo);

is($contents, <<EOF
     2	hi
     3	there
     4	b
     5	c
     6	d
EOF
, 'Offset works');

#>"

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
`touch /tmp/pt-script.pid`;
$output = `$cmd --pid /tmp/pt-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/pt-script.pid already exists},
   'Dies if PID file already exists (issue 391)'
);
unlink '/tmp/pt-script.pid';

# #############################################################################
# Done.
# #############################################################################
done_testing;
exit;
