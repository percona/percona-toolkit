#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

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
# Bug 1103045: pt-query-digest fails to parse non-SQL errors
# https://bugs.launchpad.net/percona-toolkit/+bug/1103045
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump043.txt',
         '--report-format', 'header,query_report,profile',
         qw(--watch-server 127.0.0.1:12345)) },
      "t/pt-query-digest/samples/tcpdump043_report.txt"
   ),
   'Analysis for tcpdump043 with connection error (bug 1103045)'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump044.txt',
         '--report-format', 'header,query_report,profile',
         qw(--watch-server 100.0.0.1)) },
      "t/pt-query-digest/samples/tcpdump044_report.txt"
   ),
   'Analysis for tcpdump044 with connection error (bug 1103045)'
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
