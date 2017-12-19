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
require "$trunk/bin/pt-query-digest";

my $sample = "$trunk/t/pt-query-digest/samples/pt-234-profile.log";
my @args   = ( '--report-format', 'header,query_report,profile', '--type', 'genlog', $sample );

my ($output, $exit_status) = full_output(
      sub { pt_query_digest::main(@args) },
      stderr => 1,
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args) },
      "t/pt-query-digest/samples/pt-234.log",
   ),
   'Parse genlog having timestamps with TZ'
);

# #############################################################################
# Done.
# #############################################################################
exit;
