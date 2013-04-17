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

my $cmd  = "$trunk/bin/pt-query-digest";
my $help = qx{$cmd --help};

my $output;

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/885382
# pt-query-digest --embedded-attributes doesn't check cardinality
# #############################################################################
my $sample = "$trunk/t/lib/samples/slowlogs/";

my @options = qw(
   --report-format=query_report
   --limit 10
   --group-by file
);

$output = `$cmd @options --embedded-attributes '-- .*' $sample.slow010.txt`;

like $output,
   qr/\Q--embedded-attributes should be passed two comma-separated patterns, got 1/,
   'Bug 885382: --embedded-attributes cardinality';

$output = `$cmd @options --embedded-attributes '-- .*,(?{1234})' $sample.slow010.txt`;

like $output,
   qr/\Q--embedded-attributes Eval-group /,
   "Bug 885382: --embedded-attributes rejects invalid patterns early";

$output = `$cmd @options --embedded-attributes '-- .*,(?*asdasd' $sample.slow010.txt`;

like $output,
   qr/\Q--embedded-attributes Sequence (?*...) not recognized/,
   "Bug 885382: --embedded-attributes rejects invalid patterns early";

$output = `$cmd @options --embedded-attributes '-- .*,[:alpha:]' $sample.slow010.txt`;

like $output,
   qr/\Q--embedded-attributes POSIX syntax [: :] belongs inside character/,
   "Bug 885382: --embedded-attributes rejects warning patterns early";;


# We removed --statistics, but they should still print out if we use PTDEBUG.

$output = qx{PTDEBUG=1 $cmd --no-report ${sample}slow002.txt 2>&1};
my $stats = load_file("t/pt-query-digest/samples/stats-slow002.txt");

like(
   $output,
   qr/\Q$stats\E/m,
   'PTDEBUG shows --statistics for slow002.txt',
);

like(
   $output,
   qr/Pipeline profile/m,
   'PTDEBUG shows --pipeline-profile'
);

# #############################################################################
# pt-query-digest help output mangled
# https://bugs.launchpad.net/percona-toolkit/+bug/831525
# #############################################################################

like(
   $help,
   qr/\Q--report-format=A\E\s*
      \QPrint these sections of the query analysis\E\s*
      \Qreport (default rusage\E,\s*date,\s*hostname,\s*files,\s*
      header,\s*profile,\s*query_report,\s*prepared\)/x,
   "Bug 831525: pt-query-digest help output mangled"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
