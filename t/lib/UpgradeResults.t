#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use UpgradeResults;
use PerconaTest;

my $output;
my $samples = "t/lib/samples/UpgradeResults";

my $r = new UpgradeResults(
   max_class_size => 100,
   max_examples   => 3,
);

# #############################################################################
# _format_query_times()
# #############################################################################

$output = UpgradeResults::_format_query_times(
   [
      '0.000812',
      '0.039595',
      '48.8'
   ],
);

ok(
   no_diff(
      $output,
      "$samples/format_query_times001",
      cmd_output => 1,
   ),
   "format_query_times001"
) or diag($test_diff);

# #############################################################################
# Done.
# #############################################################################
done_testing;
