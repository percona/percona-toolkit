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

like(
   `$trunk/bin/pt-mext 2>&1`,
   qr/Usage:/,
   'It runs'
);

my $cmd    = "$trunk/bin/pt-mext";
my $sample = "$trunk/t/pt-mext/samples";

ok(
   no_diff(
      "$cmd -- cat $sample/mext-001.txt",
      "t/pt-mext/samples/mext-001-result.txt",
      post_pipe => "LANG=C sort -k1,1",
   ),
   "mext-001"
) or diag($test_diff);

ok(
   no_diff(
      "$cmd -r -- cat $sample/mext-002.txt",
      "t/pt-mext/samples/mext-002-result.txt",
      post_pipe => "LANG=C sort -k1,1",
   ),
   "mext-002 -r"
) or diag($test_diff);

# #############################################################################
# Done.
# #############################################################################
done_testing;
exit;
