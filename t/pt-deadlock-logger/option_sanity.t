#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 3;

use MaatkitTest;

my $output;

# #############################################################################
# Sanity tests.
# #############################################################################
$output = `$trunk/bin/pt-deadlock-logger --dest D=test,t=deadlocks 2>&1`;
like(
   $output,
   qr/Missing or invalid source host/,
   'Requires source host'
);

$output = `$trunk/bin/pt-deadlock-logger h=127.1 --dest t=deadlocks 2>&1`;
like(
   $output,
   qr/requires a 'D'/, 
   'Dest DSN requires D',
);

$output = `$trunk/bin/pt-deadlock-logger --dest D=test 2>&1`;
like(
   $output,
   qr/requires a 't'/,
   'Dest DSN requires t'
);

# #############################################################################
# Done.
# #############################################################################
exit;
