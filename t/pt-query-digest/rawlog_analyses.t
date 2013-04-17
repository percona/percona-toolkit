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

require "$trunk/bin/pt-query-digest";

# #############################################################################
# Issue 172: Make mk-query-digest able to read raweral logs
# #############################################################################

my @args   = ('--report-format', 'header,query_report,profile', '--type', 'rawlog');
my $sample = "$trunk/t/lib/samples/rawlogs/";

# --help exists so don't run mqd as a module else --help's exit will
# exit this test script.
like(
   `$trunk/bin/pt-query-digest --type rawlog rawlog001.txt --help`,
   qr/--order-by\s+Query_time:cnt/,
   '--order-by defaults to Query_time:cnt for --type rawlog',
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'rawlog001.txt') },
      "t/pt-query-digest/samples/rawlog001.txt"
   ),
   'Analysis for rawlog001',
);

# #############################################################################
# Done.
# #############################################################################
exit;
