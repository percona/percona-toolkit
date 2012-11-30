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

my @args   = qw(--no-report --statistics);
my $sample = "$trunk/t/lib/samples/slowlogs/";

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow002.txt') },
      "t/pt-query-digest/samples/stats-slow002.txt"
   ),
   '--statistics for slow002.txt',
);

# #############################################################################
# Done.
# #############################################################################
exit;
