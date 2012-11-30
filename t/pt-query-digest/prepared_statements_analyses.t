#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 7;

use PerconaTest;

require "$trunk/bin/pt-query-digest";

my @args   = qw(--type tcpdump --report-format=query_report --limit 10 --watch-server 127.0.0.1:12345);
my $sample = "$trunk/t/lib/samples/tcpdump/";

# #############################################################################
# Issue 740: Handle prepared statements
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump021.txt') },
      "t/pt-query-digest/samples/tcpdump021.txt"
   ),
   'Analysis for tcpdump021 with prepared statements'
);
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump022.txt') },
      "t/pt-query-digest/samples/tcpdump022.txt"
   ),
   'Analysis for tcpdump022 with prepared statements'
);
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump023.txt') },
      "t/pt-query-digest/samples/tcpdump023.txt"
   ),
   'Analysis for tcpdump023 with prepared statements'
);
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump024.txt') },
      "t/pt-query-digest/samples/tcpdump024.txt"
   ),
   'Analysis for tcpdump024 with prepared statements'
);
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump025.txt') },
      "t/pt-query-digest/samples/tcpdump025.txt"
   ),
   'Analysis for tcpdump025 with prepared statements'
);
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump033.txt',
         '--report-format', 'header,query_report,profile,prepared') },
      "t/pt-query-digest/samples/tcpdump033.txt"
   ),
   'Analysis for tcpdump033 with prepared statements report'
);

# ############################################################################
# Bug 887688: Prepared statements crash pt-query-digest
# ############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'tcpdump041.txt',
         '--report-format', 'header,query_report,profile,prepared') },
      "t/pt-query-digest/samples/tcpdump041.txt",
   ),
   'Analysis for tcpdump041 (bug 887688)'
);

# #############################################################################
# Done.
# #############################################################################
exit;
