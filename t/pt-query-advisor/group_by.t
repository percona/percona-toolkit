#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 3;

use PerconaTest;
shift @INC;  # These two shifts are required for tools that use base and
shift @INC;  # derived classes.  See mk-query-digest/t/101_slowlog_analyses.t
require "$trunk/bin/pt-query-advisor";

ok(
   no_diff(
      sub { pt_query_advisor::main(
         qw(--group-by none),
         "$trunk/t/pt-query-advisor/samples/slow001.txt",) },
      "t/pt-query-advisor/samples/group-by-none-001.txt",
   ),
   "group by none"
);

ok(
   no_diff(
      sub { pt_query_advisor::main(
         "$trunk/t/pt-query-advisor/samples/slow001.txt",) },
      "t/pt-query-advisor/samples/group-by-rule-id-001.txt",
   ),
   "group by rule id (default)"
);

ok(
   no_diff(
      sub { pt_query_advisor::main(
         qw(--group-by query_id),
         "$trunk/t/pt-query-advisor/samples/slow001.txt",) },
      "t/pt-query-advisor/samples/group-by-query-id-001.txt",
   ),
   "group by query_id"
);

# #############################################################################
# Done.
# #############################################################################
exit;
