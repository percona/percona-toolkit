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

unlink('/tmp/pt-fifo-split');

my $cmd = "$trunk/bin/pt-fifo-split";

my $output = `$cmd --help`;
like($output, qr/Options and values/, 'It lives');

system("($cmd --lines 10000 $trunk/bin/pt-fifo-split > /dev/null 2>&1 < /dev/null)&");
sleep(1);

open my $fh, '<', '/tmp/pt-fifo-split' or die $OS_ERROR;
my $contents = do { local $INPUT_RECORD_SEPARATOR; <$fh>; };
close $fh;

open my $fh2, '<', "$trunk/bin/pt-fifo-split" or die $OS_ERROR;
my $contents2 = do { local $INPUT_RECORD_SEPARATOR; <$fh2>; };
close $fh2;

ok($contents eq $contents2, 'I read the file');

system("($cmd $trunk/t/pt-fifo-split/samples/file_with_lines --offset 2 > /dev/null 2>&1 < /dev/null)&");
sleep(1);

open $fh, '<', '/tmp/pt-fifo-split' or die $OS_ERROR;
$contents = do { local $INPUT_RECORD_SEPARATOR; <$fh>; };
close $fh;

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
`rm -rf /tmp/pt-script.pid`;

# #############################################################################
# Done.
# #############################################################################
exit;
