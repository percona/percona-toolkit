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
require "$trunk/bin/pt-query-digest";

my @args   = ('--report-format', 'query_report,profile', qw(--limit 10));
my $sample = "$trunk/t/lib/samples/slowlogs/";

ok(
   no_diff(
      sub { pt_query_digest::main(@args, qw(--report-histogram Lock_time),
         qw(--order-by Lock_time:sum), $sample.'slow034.txt') },
      "t/pt-query-digest/samples/slow034-order-by-Locktime-sum-with-Locktime-distro.txt",
   ),
   '--report-histogram Lock_time'
);

# #############################################################################
# Done.
# #############################################################################
exit;
