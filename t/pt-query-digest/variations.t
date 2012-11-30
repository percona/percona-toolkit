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

my $in   = "$trunk/t/lib/samples/slowlogs/";
my $out  = "t/pt-query-digest/samples/";
my @args = qw(--variations arg --limit 5 --report-format query_report);

# #############################################################################
# Issue 511: Make mk-query-digest report number of query variations
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, "$in/slow053.txt") },
      "$out/slow053.txt"
   ),
   "Variations in slow053.txt"
);

# #############################################################################
# Done.
# #############################################################################
exit;
