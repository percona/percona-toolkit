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
require "$trunk/bin/pt-table-checksum";

my $output;

# Test DSN value inheritance
$output = `$trunk/bin/pt-table-checksum h=127.1 --replicate table`;
like(
   $output,
   qr/--replicate table must be database-qualified/,
   "--replicate table must be db-qualified"
);

$output = `$trunk/bin/pt-table-checksum h=127.1 --replicate test.checksum --throttle-method foo`;
like(
   $output,
   qr/Invalid --throttle-method: foo/,
   "Invalid --throttle-method"
);

# #############################################################################
# Done.
# #############################################################################
exit;
