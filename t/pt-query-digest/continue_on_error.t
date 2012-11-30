#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 3;

use PerconaTest;
require "$trunk/bin/pt-query-digest";

my $output;

# Test --continue-on-error.
$output = `$trunk/bin/pt-query-digest --no-continue-on-error --type tcpdump $trunk/t/pt-query-digest/samples/bad_tcpdump.txt 2>&1`;
unlike(
   $output,
   qr/Query 1/,
   'Does not continue on error with --no-continue-on-error'
);

$output = `$trunk/bin/pt-query-digest --type tcpdump $trunk/t/pt-query-digest/samples/bad_tcpdump.txt 2>&1`;
like(
   $output,
   qr/paris in the the spring/,
   'Continues on error by default'
);

# #############################################################################
# Infinite loop in pt-query-digest if a report crashe
# https://bugs.launchpad.net/percona-toolkit/+bug/888114
# #############################################################################

# This bug is due to the fact that --continue-on-error is on by default.
# To reproduce the problem, we must intentionally crash pt-query-digest
# in the right place, which means we're using another bug:a
$output = output(
   sub { pt_query_digest::main("$trunk/t/lib/samples/slowlogs/slow002.txt",
      "--expected-range", "'',''") },
   stderr => 1,
);

like(
   $output,
   qr/Argument \S+ isn't numeric/,
   "Report crashed, but no infinite loop (bug 888114)"
); 

# #############################################################################
# Done.
# #############################################################################
exit;
