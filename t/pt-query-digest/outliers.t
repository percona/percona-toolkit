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

my @args   = qw(--report-format=query_report);
my $sample = "$trunk/t/lib/samples/slowlogs/";

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow013.txt',
            qw(--group-by user --outliers Query_time:.0000001:1)) },
      "t/pt-query-digest/samples/slow013_report_outliers.txt"
   ),
   'slow013 --outliers'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow049.txt',
            qw(--limit 2 --outliers Query_time:5:3),
            '--report-format', 'header,profile,query_report') },
      "t/pt-query-digest/samples/slow049.txt",
   ),
   'slow049 --outliers'
);

# #############################################################################
# Done.
# #############################################################################
exit;
