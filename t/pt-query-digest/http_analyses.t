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

use MaatkitTest;

my $run_with = "$trunk/bin/pt-query-digest --report-format=query_report --type http --limit 10 $trunk/t/lib/samples/http/";

ok(
   no_diff($run_with.'http_tcpdump002.txt', "t/pt-query-digest/samples/http_tcpdump002.txt"),
   'Analysis for http_tcpdump002.txt'
);

# #############################################################################
# Done.
# #############################################################################
exit;
