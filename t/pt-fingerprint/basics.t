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
require "$trunk/bin/pt-fingerprint";

my @args   = qw(--report-format=query_report --limit 10);
my $sample = "$trunk/t/lib/samples/slowlogs/";
my $output;

$output = `$trunk/bin/pt-fingerprint --help`;
like(
   $output,
   qr/--help/,
   "It runs"
);

# #############################################################################
# Done.
# #############################################################################
exit;
