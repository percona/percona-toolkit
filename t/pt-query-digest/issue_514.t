#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 1;

use PerconaTest;

my $run_with = "$trunk/bin/pt-query-digest --report-format=query_report --limit 10 $trunk/t/lib/samples/slowlogs/";
my $cmd;
my $output;

# #############################################################################
# Issue 514: mk-query-digest does not create handler sub for new auto-detected
# attributes
# #############################################################################
# This issue actually introduced --check-attributes-limit.
$cmd = "${run_with}slow030.txt";
local $ENV{PT_QUERY_DIGEST_CHECK_ATTRIB_LIMIT} = 100;
$output = `$cmd 2>&1`;
unlike(
   $output,
   qr/IDB IO rb/,
   '--check-attributes-limit (issue 514)'
);

# #############################################################################
# Done.
# #############################################################################
exit;
