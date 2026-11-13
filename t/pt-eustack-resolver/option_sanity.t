#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;

# ############################################################################
# We only check basic option sanity here. It is hard to create tests for the
# eu-stack output that work in all environments. So we will simply check that
# the help and version options work as expected.
# ############################################################################

my $output = `$trunk/bin/pt-eustack-resolver --help`;

like(
   $output,
   qr/^\s+--help\s+Show help and exit/m,
   "--help option is documented"
);

like(
   $output,
   qr/^\s+--version\s+Show version and exit/m,
   "--version option is documented"
);

like(
   $output,
   qr/Options and values after processing arguments:/m,
   "Help output contains expected section"
);

# ############################################################################
# Check error when no arguments are provided
# ############################################################################
my $error_output = `$trunk/bin/pt-eustack-resolver 2>&1`;

like(
   $error_output,
   qr/A PID must be specified/m,
   "Error message shown when no PID is provided"
);

like(
   $error_output,
   qr/Usage: pt-eustack-resolver PID/m,
   "Usage line shown in error"
);

# ############################################################################
# Check --version option
# ############################################################################
my $version_output = `$trunk/bin/pt-eustack-resolver --version`;

like(
   $version_output,
   qr/pt-eustack-resolver \d+\.\d+\.\d+(?:-\d+)?/m,
   "--version shows tool name and version"
);

done_testing;
