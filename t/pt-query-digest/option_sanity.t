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

# #############################################################################
# Test cmd line op sanity.
# #############################################################################
my $output = `$trunk/bin/pt-query-digest --review h=127.1,P=12345,u=msandbox,p=msandbox`;
like($output, qr/--review DSN requires a D/, 'Dies if no D part in --review DSN');

$output = `$trunk/bin/pt-query-digest --review h=127.1,P=12345,u=msandbox,p=msandbox,D=test`;
like($output, qr/--review DSN requires a D/, 'Dies if no t part in --review DSN');

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

$output = `$trunk/bin/pt-query-digest @options --embedded-attributes '-- .*' $sample.slow010.txt`;

like $output,
   qr/\Q--embedded-attributes should be passed two comma-separated patterns, got 1/,
   'Bug 885382: --embedded-attributes cardinality';

$output = `$trunk/bin/pt-query-digest @options --embedded-attributes '-- .*,(?{1234})' $sample.slow010.txt`;

like $output,
   qr/\Q--embedded-attributes Eval-group /,
   "Bug 885382: --embedded-attributes rejects invalid patterns early";

$output = `$trunk/bin/pt-query-digest @options --embedded-attributes '-- .*,(?*asdasd' $sample.slow010.txt`;

like $output,
   qr/\Q--embedded-attributes Sequence (?*...) not recognized/,
   "Bug 885382: --embedded-attributes rejects invalid patterns early";

$output = `$trunk/bin/pt-query-digest @options --embedded-attributes '-- .*,[:alpha:]' $sample.slow010.txt`;

like $output,
   qr/\Q--embedded-attributes POSIX syntax [: :] belongs inside character/,
   "Bug 885382: --embedded-attributes rejects warning patterns early";;

# #############################################################################
# pt-query-digest help output mangled
# https://bugs.launchpad.net/percona-toolkit/+bug/831525
# #############################################################################

$output = `$trunk/bin/pt-query-digest --help`;

like(
   $output,
   qr/\Q--report-format=A\E\s*
      \QPrint these sections of the query analysis\E\s*
      \Qreport (default rusage,date,hostname,files,\E\s*
      \Qheader,profile,query_report,prepared)\E/x,
   "Bug 831525: pt-query-digest help output mangled"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
