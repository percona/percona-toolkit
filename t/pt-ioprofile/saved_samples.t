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

my $sample = "t/pt-ioprofile/samples";
my $output = "";

# Files with raw samples should be named N-samples.txt
# in t/pt-ioprofile/samples/.
foreach my $sampleno ( qw(003) ) {
   ok(
      no_diff(
         "$trunk/bin/pt-ioprofile $trunk/$sample/$sampleno-samples.txt",
         "$sample/$sampleno-processed.txt",
         stderr => 1,
      ),
      "$sampleno-samples.txt"
   );
}

# #############################################################################
# Done.
# #############################################################################
exit;
