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

# #############################################################################
# Issue 736: mk-query-digest doesn't handle badly distilled queries
# #############################################################################

my @args   = qw(--report-format=profile --limit 10);
my $sample = "$trunk/t/pt-query-digest/samples/";

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'cannot-distill.log') },
      "t/pt-query-digest/samples/cannot-distill-profile.txt",
   ),
   'Distill nonsense and non-SQL'
);

# #############################################################################
# Done.
# #############################################################################
exit;
