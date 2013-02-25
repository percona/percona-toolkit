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

# #############################################################################
# Issue 462: Filter out all but first N of each
# #############################################################################
ok(
   no_diff("$trunk/bin/pt-query-digest $trunk/t/lib/samples/slowlogs/slow006.txt "
      . '--no-report --output slowlog --sample 2',
      "t/pt-query-digest/samples/slow006-first2.txt"),
   'Print only first N unique occurrences with explicit --group-by',
);

# #############################################################################
# Issue 470: mk-query-digest --sample does not work with --report ''
# #############################################################################
ok(
   no_diff("$trunk/bin/pt-query-digest $trunk/t/lib/samples/slowlogs/slow006.txt "
      . '--no-report --output slowlog --sample 2',
      "t/pt-query-digest/samples/slow006-first2.txt"),
   'Print only first N unique occurrences, --no-report',
);

# #############################################################################
# Done.
# #############################################################################
exit;
