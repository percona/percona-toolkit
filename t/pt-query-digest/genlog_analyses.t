#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 4;

use PerconaTest;

require "$trunk/bin/pt-query-digest";

# #############################################################################
# Issue 172: Make mk-query-digest able to read general logs
# #############################################################################

my @args   = ('--report-format', 'header,query_report,profile', '--type', 'genlog');
my $sample = "$trunk/t/lib/samples/genlogs/";

# --help exists so don't run mqd as a module else --help's exit will
# exit this test script.
like(
   `$trunk/bin/pt-query-digest --type genlog genlog001.txt --help`,
   qr/--order-by\s+Query_time:cnt/,
   '--order-by defaults to Query_time:cnt for --type genlog',
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'genlog001.txt') },
      "t/pt-query-digest/samples/genlog001.txt"
   ),
   'Analysis for genlog001',
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'genlog002.txt') },
      "t/pt-query-digest/samples/genlog002.txt",
   ),
   'Analysis for genlog002',
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'genlog003.txt') },
      "t/pt-query-digest/samples/genlog003.txt"
   ),
   'Analysis for genlog003',
);

# #############################################################################
# Done.
# #############################################################################
exit;
