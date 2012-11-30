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
require "$trunk/bin/pt-query-advisor";

my @args = qw(--print-all --report-format full --group-by none);

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         qw(--ignore-rules COL.001),
         '--query', 'SELECT * FROM tbl WHERE id=1') },
      't/pt-query-advisor/samples/tbl-001-01-ignored.txt',
   ),
   'Ignore a rule'
);

# #############################################################################
# Done.
# #############################################################################
exit;
