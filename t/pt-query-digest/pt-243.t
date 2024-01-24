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

use PerconaTest;

my $run_with = "$trunk/bin/pt-query-digest --max-hostname-length 0 --max-line-length 100 --report-format=query_report --limit 10 $trunk/t/lib/samples/slowlogs/";

# #############################################################################
# Issue 232: mk-query-digest does not properly handle logs with an empty Schema:
# #############################################################################
my $output = 'foo'; # clear previous test results
my $cmd = "${run_with}slow-pt-243.txt";
$output = `$cmd 2>&1`;

like(
   $output,
   qr/Hosts\s+alonghotnamelikelocalhost/,
   'Hostname is not being truncated',
);

# #############################################################################
# Done.
# #############################################################################
exit;
