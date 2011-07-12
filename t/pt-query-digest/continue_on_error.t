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

my $output;

# Test --continue-on-error.
$output = `$trunk/bin/pt-query-digest --no-continue-on-error --type tcpdump $trunk/t/pt-query-digest/samples/bad_tcpdump.txt 2>&1`;
unlike(
   $output,
   qr/Query 1/,
   'Does not continue on error with --no-continue-on-error'
);

$output = `$trunk/bin/pt-query-digest --type tcpdump $trunk/t/pt-query-digest/samples/bad_tcpdump.txt 2>&1`;
like(
   $output,
   qr/paris in the the spring/,
   'Continues on error by default'
);


# #############################################################################
# Done.
# #############################################################################
exit;
