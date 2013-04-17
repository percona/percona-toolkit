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
require "$trunk/bin/pt-table-usage";

my @args   = qw();
my $in     = "$trunk/t/pt-table-usage/samples/in";
my $out    = "t/pt-table-usage/samples/out";
my $output = '';

# ############################################################################
# Test --create-table-definitions
# ############################################################################

# Without --create-table-definitions, the tables wouldn't be db-qualified.
ok(
   no_diff(
      sub { pt_table_usage::main(@args,
         '--query', 'select city from city where city="New York"',
         '--create-table-definitions',
            "$trunk/t/lib/samples/mysqldump-no-data/all-dbs.txt") },
      "$out/create-table-defs-001.txt",
   ),
   '--create-table-definitions'
);

# #############################################################################
# Done.
# #############################################################################
exit;
