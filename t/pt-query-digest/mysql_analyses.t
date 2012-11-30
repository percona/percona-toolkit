#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 6;

use PerconaTest;

require "$trunk/bin/pt-query-digest";

my @args   = qw(--type tcpdump --report-format=query_report --limit 10);
my $sample = "$trunk/t/lib/samples/tcpdump/";

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump003.txt') },
      "t/pt-query-digest/samples/tcpdump003.txt"
   ),
   'Analysis for tcpdump003 with numeric Error_no'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump001.txt',
         qw(--watch-server 127.0.0.1)) },
      "t/pt-query-digest/samples/tcpdump001.txt",
   ),
   'Analysis for tcpdump001 with --watch-server ip'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump012.txt',
         qw(--watch-server 192.168.1.1:3307)) },
      "t/pt-query-digest/samples/tcpdump012.txt",
   ),
   'Analysis for tcpdump012 with --watch-server ip:port'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump012.txt',
         qw(--watch-server 192.168.1.1.3307)) },
      "t/pt-query-digest/samples/tcpdump012.txt",
   ),
   'Analysis for tcpdump012 with --watch-server ip.port'
);

# #############################################################################
# Issue 228: parse tcpdump.
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump002.txt') },
      "t/pt-query-digest/samples/tcpdump002_report.txt"
   ),
   'Analysis for tcpdump002',
);

# #############################################################################
# Issue 398: Fix mk-query-digest to handle timestamps that have microseconds
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump017.txt',
         '--report-format', 'header,query_report,profile') },
      "t/pt-query-digest/samples/tcpdump017_report.txt"
   ),
   'Analysis for tcpdump017 with microsecond timestamps (issue 398)'
);

# #############################################################################
# Done.
# #############################################################################
exit;
