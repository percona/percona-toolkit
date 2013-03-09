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

my $run_with = "$trunk/bin/pt-query-digest --report-format=query_report --limit 10 $trunk/t/lib/samples/slowlogs/";

# #############################################################################
# Issue 479: Make mk-query-digest carry Schema and ts attributes along the
# pipeline
# #############################################################################
ok(
   no_diff($run_with.'slow034.txt --no-report --output slowlog', "t/pt-query-digest/samples/slow034-inheritance.txt"),
   'Analysis for slow034 with inheritance'
);

# Make sure we can turn off some default inheritance, 'ts' in this test.
ok(
   no_diff($run_with.'slow034.txt --no-report --output slowlog --inherit-attributes db', "t/pt-query-digest/samples/slow034-no-ts-inheritance.txt"),
   'Analysis for slow034 without default ts inheritance'
);

# #############################################################################
# Done.
# #############################################################################
exit;
