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
# Done.
# #############################################################################
exit;
