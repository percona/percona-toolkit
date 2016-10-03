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
require "$trunk/bin/pt-query-digest";

my @args   = qw(--report-format=profile --limit=10);
my $sample = "$trunk/t/pt-query-digest/samples/";

ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'issue_1604834.log') },
      "t/pt-query-digest/samples/issue_1604834-1.txt",
   ),
   'Distill nonsense and non-SQL'
);

@args   = qw(--report-format=profile --limit=10 --preserve-embedded-numbers);
ok(
   no_diff(
      sub { pt_query_digest::main(@args, $sample.'issue_1604834.log') },
      "t/pt-query-digest/samples/issue_1604834-2.txt",
   ),
   'Distill nonsense and non-SQL'
);
# #############################################################################
# Done.
# #############################################################################
exit;
