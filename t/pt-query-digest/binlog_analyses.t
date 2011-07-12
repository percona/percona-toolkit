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

# See 101_slowlog_analyses.t or http://code.google.com/p/maatkit/wiki/Testing
shift @INC;  # our unshift (above)
shift @INC;  # PerconaTest's unshift

require "$trunk/bin/pt-query-digest";

# #############################################################################
# Issue 476: parse binary logs.
# #############################################################################
# We want the profile report so we can check that queries like
# CREATE DATABASE are distilled correctly.
my @args   = ('--report-format', 'header,query_report,profile', '--type', 'binlog');
my $sample = "$trunk/t/lib/samples/binlogs/";

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'binlog001.txt') },
      "t/pt-query-digest/samples/binlog001.txt"
   ),
   'Analysis for binlog001',
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'binlog002.txt') },
      "t/pt-query-digest/samples/binlog002.txt"
   ),
   'Analysis for binlog002',
);

# #############################################################################
# Done.
# #############################################################################
exit;
