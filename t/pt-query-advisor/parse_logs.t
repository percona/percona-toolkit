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
require "$trunk/bin/pt-query-advisor";

my $output;
my @args   = ();
my $sample = "$trunk/t/lib/samples/";

$output = output(
   sub { pt_query_advisor::main(@args, "$sample/slowlogs/slow018.txt") },
);
like(
   $output,
   qr/COL.002/,
   "Parse slowlog"
);

$output = output(
   sub { pt_query_advisor::main(@args, qw(--type genlog),
      "$sample/genlogs/genlog001.txt") },
);
like(
   $output,
   qr/CLA.005/,
   "Parse genlog"
);

# #############################################################################
# pt-query-advisor hangs on big queries
# https://bugs.launchpad.net/percona-toolkit/+bug/823431
# #############################################################################

my $exit_status;
$output = output(
   sub { $exit_status = pt_query_advisor::main(@args,
      "$sample/bug_823431.log")
   },
   stderr => 1
);

ok(
   !$exit_status,
   "Bug 823431: ptqa doesn't hang on a big query"
);

is(
   $output,
   '',
   "Bug 823431: ptqa doesn't hang on a big query and doesn't find an incorrect rule"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
