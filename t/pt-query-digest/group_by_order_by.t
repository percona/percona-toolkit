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

use PerconaTest;

my $output;

# #############################################################################
# Test that --group-by cascades to --order-by.
# #############################################################################
$output = `$trunk/bin/pt-query-digest --group-by foo,bar --help`;
like($output, qr/--order-by\s+Query_time:sum,Query_time:sum/,
   '--group-by cascades to --order-by');

$output = `$trunk/bin/pt-query-digest --no-report --help 2>&1`;
like(
   $output,
   qr/--group-by\s+fingerprint/,
   "Default --group-by with --no-report"
);

# #############################################################################
# Issue 984: --order-by breaks the Query_time distribution graph
# #############################################################################
ok(
   no_diff(
      "$trunk/bin/pt-query-digest --report-format=query_report $trunk/t/lib/samples/slowlogs/slow006.txt --order-by Rows_examined",
      "t/pt-query-digest/samples/slow006-order-by-re.txt",
   ),
   "--group-by does not change distro chart (issue 984)"
);

# #############################################################################
# Done.
# #############################################################################
exit;
