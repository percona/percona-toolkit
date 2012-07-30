#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 4;

use PerconaTest;
require "$trunk/bin/pt-fifo-split";

my $fifo = '/tmp/pt-fifo-split';
unlink($fifo);

my $cmd = "$trunk/bin/pt-fifo-split";

my $output = `$cmd --help`;
like($output, qr/Options and values/, 'It lives');

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
exit;
