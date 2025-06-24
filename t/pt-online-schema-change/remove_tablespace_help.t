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

require "$trunk/bin/pt-online-schema-change";

plan tests => 2;

# #############################################################################
# Test that --remove-tablespace option is documented in help
# #############################################################################

my ($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main('--help') },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Help command exits successfully"
);

like(
   $output,
   qr/--remove-tablespace/,
   "Help output includes --remove-tablespace option"
);

done_testing; 