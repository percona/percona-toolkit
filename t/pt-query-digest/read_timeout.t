#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 2;

use PerconaTest;

use Time::HiRes qw(sleep time);

# #########################################################################
# Issue 226: Fix mk-query-digest signal handling
# #########################################################################
diag(`rm -rf /tmp/mqd.pid`);

my ($start, $end, $waited);
my $timeout = wait_for(
   sub {
      $start = time;
      `$trunk/bin/pt-query-digest --read-timeout 2 --pid /tmp/mqd.pid 2>/dev/null`;
      return;
   },
   5,
);
$end    = time;
$waited = $end - $start;
if ( $timeout ) {
   # mqd ran longer than --read-timeout
   my $pid = `cat /tmp/mqd.pid`;
   `kill $pid`;
}

ok(
   $waited >= 2 && int($waited) < 4,
   sprintf("--read-timeout 2 waited %.1f seconds reading STDIN", $waited)
);

diag(`rm -rf /tmp/mqd.pid`);
diag(`rm -rf /tmp/mqd.fifo; mkfifo /tmp/mqd.fifo`);
system("$trunk/t/pt-query-digest/samples/write-to-fifo.pl /tmp/mqd.fifo 4 &");

$timeout = wait_for(
   sub {
      $start = time;
      `$trunk/bin/pt-query-digest --read-timeout 2 --pid /tmp/mqd.pid /tmp/mqd.fifo`;
      return;
   },
   5,
);
$end    = time;
$waited = $end - $start;
if ( $timeout ) {
   # mqd ran longer than --read-timeout
   my $pid = `cat /tmp/mqd.pid`;
   `kill $pid`;
}

ok(
   $waited >= 2 && int($waited) < 4,
   sprintf("--read-timeout waited %.1f seconds reading a file", $waited)
);

diag(`rm -rf /tmp/mqd.pid`);
diag(`rm -rf /tmp/mqd.fifo`);

# #############################################################################
# Done.
# #############################################################################
exit;
