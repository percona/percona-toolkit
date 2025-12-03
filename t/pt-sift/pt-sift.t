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

my ($tool) = $PROGRAM_NAME =~ m/([\w-]+)\.t$/;

my $output = `$trunk/bin/$tool $trunk/bin 2>&1`;

# https://perconadev.atlassian.net/browse/PT-2498
# We do not test interactive tool here
# But we at least ensure it works and prints
# proper error message if called without correct path
isnt(
   $?,
   0,
   "Error for the directory that does not contain pt-stalk files"
) or diag($output);

like(
   $output,
   qr/Error: There are no pt-stalk files in $trunk\/bin/,
   "Correct error message"
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
exit;
