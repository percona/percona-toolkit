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

# #############################################################################
# First, some basic input-output diffs to make sure that
# the analysis reports are correct.
# #############################################################################

my @args   = qw(--report-format=query_report --limit 10);
my $sample = "$trunk/t/lib/samples/slowlogs/";

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'empty') },
      "t/pt-query-digest/samples/empty_report.txt",
   ),
   'Analysis for empty log'
) or diag($test_diff);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow001.txt', '--expected-range', '2,10') },
      "t/pt-query-digest/samples/slow001_report.txt"
   ),
   'Analysis for slow001 with --expected-range'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow001.txt', qw(--group-by tables)) },
      "t/pt-query-digest/samples/slow001_tablesreport.txt"
   ),
   'Analysis for slow001 with --group-by tables'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow001.txt', qw(--group-by distill)) },
      "t/pt-query-digest/samples/slow001_distillreport.txt"
   ),
   'Analysis for slow001 with distill'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow002.txt',
            qw(--group-by distill --timeline --no-report)) },
      "t/pt-query-digest/samples/slow002_distilltimeline.txt"
   ),
   'Timeline for slow002 with distill'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow002.txt') },
      "t/pt-query-digest/samples/slow002_report.txt"
   ),
   'Analysis for slow002'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow002.txt',
               '--filter', '$event->{arg} =~ m/fill/') },
      "t/pt-query-digest/samples/slow002_report_filtered.txt"
   ),
   'Analysis for slow002 with --filter'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow002.txt',
               qw(--order-by Query_time:cnt --limit 2)) },
      "t/pt-query-digest/samples/slow002_orderbyreport.txt"
   ),
   'Analysis for slow002 --order-by --limit'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow003.txt') },
      "t/pt-query-digest/samples/slow003_report.txt"
   ),
   'Analysis for slow003'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow004.txt') },
      "t/pt-query-digest/samples/slow004_report.txt"
   ),
   'Analysis for slow004'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow006.txt') },
      "t/pt-query-digest/samples/slow006_report.txt"
   ),
   'Analysis for slow006'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow008.txt') },
      "t/pt-query-digest/samples/slow008_report.txt"
   ),
   'Analysis for slow008'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow010.txt',
            '--embedded-attributes', ' -- .*,(\w+): ([^\,]+)',
            qw(--group-by file)) },
      "t/pt-query-digest/samples/slow010_reportbyfile.txt"
   ),
   'Analysis for slow010 --group-by some --embedded-attributes'
);

ok(
   no_diff(
       sub { pt_query_digest::main(@args, $sample.'slow011.txt') },
       "t/pt-query-digest/samples/slow011_report.txt"
   ),
   'Analysis for slow011'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow013.txt') },
      "t/pt-query-digest/samples/slow013_report.txt"
   ),
   'Analysis for slow013'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow013.txt', qw(--group-by user)) },
      "t/pt-query-digest/samples/slow013_report_user.txt"
   ),
   'Analysis for slow013 with --group-by user'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow013.txt',
            qw(--limit 1 --report-format), 'header,query_report', '--group-by', 'fingerprint,user') },
      "t/pt-query-digest/samples/slow013_report_fingerprint_user.txt"
   ),
   'Analysis for slow013 with --group-by fingerprint,user'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow013.txt', qw(--report-format profile --limit 3)) },
      "t/pt-query-digest/samples/slow013_report_profile.txt"
   ),
   'Analysis for slow013 with profile',
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow013.txt', qw(--limit 100%:1)) },
      "t/pt-query-digest/samples/slow013_report_limit.txt"
   ),
   'Analysis for slow013 with --limit'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow014.txt') },
      "t/pt-query-digest/samples/slow014_report.txt"
   ),
   'Analysis for slow014'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow018.txt') },
      "t/pt-query-digest/samples/slow018_report.txt"
   ),
   'Analysis for slow018'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow019.txt') },
      "t/pt-query-digest/samples/slow019_report.txt"
   ),
   '--zero-admin works'
);

# This was fixed at some point by checking the fingerprint to see if the
# query needed to be converted to a SELECT.
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow023.txt') },
      "t/pt-query-digest/samples/slow023.txt"
   ),
   'Queries that start with a comment are not converted for EXPLAIN',
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow024.txt') },
      "t/pt-query-digest/samples/slow024.txt"
   ),
   'Long inserts/replaces are truncated (issue 216)',
);

# Issue 244, no output when --order-by doesn't exist
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow002.txt', qw(--order-by Rows_read:sum)) },
      "t/pt-query-digest/samples/slow002-orderbynonexistent.txt"
   ),
   'Order by non-existent falls back to default',
);

# Issue 337, duplicate table names
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow028.txt') },
      "t/pt-query-digest/samples/slow028.txt"
   ),
   'No duplicate table names',
);

# Issue 458, Use of uninitialized value in division (/) 
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow035.txt',
            '--report-format', 'header,query_report,profile') },
      "t/pt-query-digest/samples/slow035.txt"
   ),
   'Pathological all attribs, minimal attribs, all zero values (slow035)',
);

# Issue 563, Lock tables is not distilled
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow037.txt', qw(--group-by distill),
            '--report-format', 'query_report,profile') },
      "t/pt-query-digest/samples/slow037_report.txt"
   ),
   'Distill UNLOCK and LOCK TABLES'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow034.txt', qw(--order-by Lock_time:sum),
            '--report-format', 'query_report,profile') },
      "t/pt-query-digest/samples/slow034-order-by-Locktime-sum.txt",
   ),
   'Analysis for slow034 --order-by Lock_time:sum'
);

# #############################################################################
# Test a sample that at one point caused an error (trunk doesn't have the error
# now):
# Use of uninitialized value in join or string at mk-query-digest line 1713.
# or on newer Perl:
# Use of uninitialized value $verbs in join or string at mk-query-digest line
# 1713.
# The code in question is this:
#  else {
#     my ($verbs, $table)  = $self->_distill_verbs($query, %args);
#     my @tables           = $self->_distill_tables($query, $table, %args);
#     $query               = join(q{ }, $verbs, @tables);
#  }
# #############################################################################
my $output = `$trunk/bin/pt-query-digest $sample/slow041.txt >/dev/null 2>/tmp/mqd-warnings.txt`;
is(
   -s '/tmp/mqd-warnings.txt',
   0,
   'No warnings on file 041'
);
diag(`rm -rf /tmp/mqd-warnings.txt`);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow042.txt',
            qw(--report-format query_report)) },
      "t/pt-query-digest/samples/slow042-show-all-host.txt",
   ),
   'Analysis for slow042 (previously the --show-all test)'
);

# #############################################################################
# Issue 948: mk-query-digest treats InnoDB_rec_lock_wait value as number
# instead of time
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow032.txt') },
      "t/pt-query-digest/samples/slow032.txt",
   ),
   'Analysis for slow032 (issue 948)',
);

# #############################################################################
# Issue 1030: Fingerprint can remove ORDER BY ASC
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, '--report-format', 'query_report,profile',  $sample.'slow048.txt') },
      "t/pt-query-digest/samples/slow048.txt",
   ),
   'Analysis for slow048 (issue 1030)',
);

# #############################################################################
# Issue 347: A badly rewritten query  
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, '--report-format', 'query_report,profile',  $sample.'slow050.txt') },
      "t/pt-query-digest/samples/slow050.txt",
   ),
   'Analysis for slow050 (issue 347)',
);

# #############################################################################
# Issue 918: mk-query-digest does not fingerprint LOAD DATA
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, '--report-format', 'query_report,profile',  $sample.'slow051.txt') },
      "t/pt-query-digest/samples/slow051.txt",
   ),
   'Analysis for slow051 (issue 918)',
) or diag($test_diff);

# #############################################################################
# Issue 1124: Make mk-query-digest profile include variance-to-mean ratio
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, '--report-format', 'query_report,profile',  $sample.'slow052.txt') },
      "t/pt-query-digest/samples/slow052.txt",
   ),
   'Analysis for slow052 (Apdex and V/M)',
);

# #############################################################################
# Bug 821694: pt-query-digest doesn't recognize hex InnoDB txn IDs
# #############################################################################
ok(
   no_diff(
      sub {
         local $ENV{PT_QUERY_DIGEST_CHECK_ATTRIB_LIMIT} = 5;
         pt_query_digest::main(@args, $sample.'slow054.txt')
      },
      "t/pt-query-digest/samples/slow054.txt",
   ),
   'Analysis for slow054 (InnoDB_trx_id bug 821694)'
);

# #############################################################################
# Bug 924950: pt-query-digest --group-by db may crash profile report
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow055.txt',
         qw(--group-by db)) },
      "t/pt-query-digest/samples/slow055.txt",
   ),
   'Analysis for slow055 (group by blank db bug 924950)'
);

# #############################################################################
# Bug 1082599: pt-query-digest fails to parse timestamp with no query
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow056.txt') },
      "t/pt-query-digest/samples/slow056.txt",
   ),
   'Analysis for slow056 (no query bug 1082599)'
);

# #############################################################################
# Bug 1176010: pt-query-digest should know how to group quoted and unquoted
# database names
# https://bugs.launchpad.net/percona-toolkit/+bug/1176010
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow057.txt',
         qw(--group-by db)) },
      "t/pt-query-digest/samples/slow057.txt",
   ),
   'Analysis for slow057 (no grouping bug 1176010)'
) or diag($test_diff);

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/821692
# pt-query-digest doesn't distill LOAD DATA correctly 
# https://bugs.launchpad.net/percona-toolkit/+bug/984053
# pt-query-digest doesn't distill INSERT/REPLACE without INTO correctly
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main($sample.'slow058.txt',
         '--report-format', 'query_report,profile', '--limit', '100%',
      )},
      "t/pt-query-digest/samples/slow058.txt",
   ),
   'Analysis for slow058 (bug 821692, bug 984053)'
) or diag($test_diff);

# #############################################################################
# pt-query-digest support for Percona Server slow log rate limiting
# https://blueprints.launchpad.net/percona-toolkit/+spec/pt-query-digest-rate-limit
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'slow059.txt',
         '--report-format', 'header,query_report,profile')
      },
      "t/pt-query-digest/samples/slow059_report01.txt"
   ),
   'Analysis for slow059 with rate limiting'
) or diag($test_diff);

# #############################################################################
# Done.
# #############################################################################
done_testing;
