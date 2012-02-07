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
# Issue 232: mk-query-digest does not properly handle logs with an empty Schema:
# #############################################################################
my $output = 'foo'; # clear previous test results
my $cmd = "${run_with}slow026.txt";
$output = `PTDEBUG=1 $cmd 2>&1`;
# Changed qr// from matching db to Schema because attribs are auto-detected.
like(
   $output,
   qr/Type for db is string /,
   'Type for empty Schema: is string (issue 232)',
);

unlike(
   $output,
   qr/Argument "" isn't numeric in numeric gt/,
   'No error message in debug output for empty Schema: (issue 232)'
);

# #############################################################################
# Done.
# #############################################################################
exit;
