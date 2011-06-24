#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 1;

use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-log-player";

my $output;

# #############################################################################
# Issue 391: Add --pid option to all scripts
# #############################################################################
`touch /tmp/mk-script.pid`;
$output = `$trunk/bin/pt-log-player --split Thread_id $trunk/t/lib/samples/binlog001.txt --type binlog --session-files 1  --pid /tmp/mk-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/mk-script.pid already exists},
   'Dies if PID file already exists (issue 391)'
);
`rm -rf /tmp/mk-script.pid`;

# #############################################################################
# Done.
# #############################################################################
exit;
