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

use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-log-player";

my $output;
my $tmpdir = '/tmp/mk-log-player';

diag(`rm -rf $tmpdir 2>/dev/null; mkdir $tmpdir`);

# #############################################################################
# Test option sanity.
# #############################################################################
$output = `$trunk/bin/pt-log-player 2>&1`;
like(
   $output,
   qr/Specify at least one of --play, --split or --split-random/,
   'Needs --play or --split to run'
);

$output = `$trunk/bin/pt-log-player --play foo 2>&1`;
like(
   $output,
   qr/Missing or invalid host/,
   '--play requires host'
);

$output = `$trunk/bin/pt-log-player --play foo h=localhost --print 2>&1`;
like(
   $output,
   qr/foo is not a file/,
   'Dies if no valid session files are given'
);

`$trunk/bin/pt-log-player --split Thread_id --base-dir $tmpdir $trunk/t/pt-log-player/samples/log001.txt`;
`$trunk/bin/pt-log-player --threads 1 --play $tmpdir/sessions-1.txt --print`;
$output = `cat $tmpdir/*`;
like(
   $output,
   qr/use mk_log/,
   "Prints sessions' queries without DSN"
);
diag(`rm session-results-*.txt 2>/dev/null`);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -rf $tmpdir 2>/dev/null`);
exit;
