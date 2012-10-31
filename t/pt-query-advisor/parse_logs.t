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

use File::Spec;

use PerconaTest;
shift @INC;  # These two shifts are required for tools that use base and
shift @INC;  # derived classes.  See mk-query-digest/t/101_slowlog_analyses.t
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
      File::Spec->catfile($sample, "bug_823431.log"))
   });

ok(
   !$exit_status,
   "Bug 823431: pqa doesn't hang on a big query"
);

like(
   $output,
   qr/COL.002/,
   "Bug 823431: pqa doesn't hang on a big query and finds the correct rule"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
