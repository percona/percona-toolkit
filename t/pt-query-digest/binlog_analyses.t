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
) or diag($test_diff);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'binlog002.txt') },
      "t/pt-query-digest/samples/binlog002.txt"
   ),
   'Analysis for binlog002',
) or diag($test_diff);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'binlog011.txt') },
      "t/pt-query-digest/samples/binlog011.txt"
   ),
   'Analysis for binlog011 - Handles 5.6 binlog with checksum CRC32',
) or diag($test_diff);



# #############################################################################
# Issue 1377888: refuse to parse raw binary log 
# #############################################################################

my $output = output(
    sub { pt_query_digest::main(@args, "$trunk/t/lib/samples/binlogs/raw_binlog.log") },
   stderr => 1
);

like( 
   $output,
   qr/mysqlbinlog/i,
   'Refuses to parse raw binlog file'
);
    



# #############################################################################
# Done.
# #############################################################################
exit;
