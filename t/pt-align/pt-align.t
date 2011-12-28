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
require "$trunk/bin/pt-align";

foreach my $raw_file ( <$trunk/t/pt-align/samples/*-raw.txt> ) {
   my ($n) = $raw_file =~ m/(\d+)-raw\.txt/;
   ok(
      no_diff(
         sub { pt_align::main($raw_file) },
         "t/pt-align/samples/$n-aligned.txt",
         keep_output => 1,
      ),
      "Align $n-raw.txt"
   );
}

# ###########################################################################
# Done.
# ###########################################################################
exit;
