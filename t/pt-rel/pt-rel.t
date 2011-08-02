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

ok(
   no_diff(
      "cat $trunk/t/pt-rel/samples/samp01.in | $trunk/bin/pt-rel",
      "t/pt-rel/samples/samp01.out",
   ),
   "samp01"
);

# #############################################################################
# Done.
# #############################################################################
exit;
