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

use MaatkitTest;

# See 101_slowlog_analyses.t or http://code.google.com/p/maatkit/wiki/Testing
shift @INC;  # our unshift (above)
shift @INC;  # MaatkitTest's unshift

require "$trunk/bin/pt-query-digest";

# #############################################################################
# Issue 535: Make mk-query-digest able to read PostgreSQL logs
# #############################################################################

my @args   = qw(--report-format profile --type pglog);
my $sample = "$trunk/t/lib/samples/pg/";

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'pg-log-009.txt') },
      "t/pt-query-digest/samples/pg-sample1"
   ),
   'Analysis for pg-log-009.txt',
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'pg-syslog-008.txt') },
      "t/pt-query-digest/samples/pg-syslog-sample1"
   ),
   'Analysis for pg-syslog-008.txt',
);

# #############################################################################
# Done.
# #############################################################################
exit;
