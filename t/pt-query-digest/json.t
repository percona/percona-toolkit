#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
   $ENV{PTTEST_PRETTY_JSON} = 0;
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
require "$trunk/bin/pt-query-digest";

no warnings 'once';
local $JSONReportFormatter::sorted_json = 1;
local $JSONReportFormatter::pretty_json = 0;

my @args    = qw(--output json);
my $sample  = "$trunk/t/lib/samples";
my $results = "t/pt-query-digest/samples/json";

my $escaped_trunk = $trunk;
$escaped_trunk =~ s/\//\\\\\//g;

#1
ok(
   no_diff(
      sub { pt_query_digest::main(@args, "$sample/slowlogs/empty") },
      "t/pt-query-digest/samples/empty_json_report.txt",
   ),
   'json output for empty log'
) or diag($test_diff);

#2
ok(
   no_diff(
      sub { pt_query_digest::main(@args, "$sample/slowlogs/slow002.txt") },
      "$results/slow002.txt",
      sed => [ q/'s!"name":".*slow002.txt"!"name":"slow002.txt"!'/ ],
   ),
   'json output for slow002'
) or diag($test_diff);

#3
ok(
   no_diff(
      sub { pt_query_digest::main(qw(--no-vertical-format), @args,
                                  "$sample/slowlogs/slow002.txt") },
      "$results/slow002_no_vertical.txt",
      sed => [ q/'s!"name":".*slow002.txt"!"name":"slow002.txt"!'/ ],
   ),
   'json output for slow002 with --no-vertical-format'
) or diag($test_diff);

ok(
   no_diff(
      sub { pt_query_digest::main(qw(--output json-anon),
         "$sample/slowlogs/slow002.txt") },
      "$results/slow002-anon.txt",
      sed => [ q/'s!"name":".*slow002.txt"!"name":"slow002.txt"!'/ ],
   ),
   'json-anon output for slow002'
) or diag($test_diff);
ok(
   no_diff(
      sub { pt_query_digest::main(qw(--output json-anon --no-vertical-format),
         "$sample/slowlogs/slow002.txt") },
      "$results/slow002-anon_no_vertical.txt",
      sed => [ q/'s!"name":".*slow002.txt"!"name":"slow002.txt"!'/ ],
   ),
   'json-anon output for slow002 with --no-vertical-format'
) or diag($test_diff);

# --type tcpdump

ok(
   no_diff(
      sub { pt_query_digest::main(qw(--type tcpdump --limit 10 --watch-server 127.0.0.1:12345),
                                  @args, "$sample/tcpdump/tcpdump021.txt") },
      "$results/tcpdump021.txt",
      sed => [ q/'s!"name":".*tcpdump021.txt"!"name":"tcpdump021.txt"!'/ ],
   ),
   'json output for for tcpdump021',
) or diag($test_diff);

# #############################################################################
# pt-query-digest support for Percona Server slow log rate limiting
# https://blueprints.launchpad.net/percona-toolkit/+spec/pt-query-digest-rate-limit
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args,
               "$trunk/t/lib/samples/slowlogs/slow059.txt",
               qw(--output json))
      },
      "t/pt-query-digest/samples/slow059_report02.txt",
      sed => [ q/'s!"name":".*slow059.txt"!"name":"slow059.txt"!'/ ],
   ),
   'json output for slow059'
) or diag($test_diff);

# #############################################################################
# Done.
# #############################################################################
done_testing;
