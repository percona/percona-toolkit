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
      post_pipe => "LOCALE=en_US.utf8 LANG=en_US.UTF-8 sort -k1,1",
   ),
   "mext-001"
) or diag($test_diff);

ok(
   no_diff(
      "$cmd -r -- cat $sample/mext-002.txt",
      "t/pt-mext/samples/mext-002-result.txt",
      post_pipe => "LOCALE=en_US.utf8 LANG=en_US.UTF-8 sort -k1,1",
   ),
   "mext-002 -r"
) or diag($test_diff);

ok(
   no_diff(
      "$cmd -- cat $sample/pt-130-in.txt",
      "t/pt-mext/samples/pt-130-out.txt",
      post_pipe => "LOCALE=en_US.utf8 LANG=en_US.UTF-8 sort -k1,1",
   ),
   "having rsa key",
) or diag($test_diff);

# #############################################################################
# PT-1731: Add min/max/avg/std/sum to each line for pt-mext
# #############################################################################
ok(
   no_diff(
      "$cmd --aggregations -- cat $sample/pt-1731-in.txt",
      "t/pt-mext/samples/pt-1731-out.txt",
   ),
   "PT-1731 --aggregations",
) or diag($test_diff);

ok(
   no_diff(
      "$cmd -r -a -- cat $sample/pt-1731-in.txt",
      "t/pt-mext/samples/pt-1731-relative-out.txt",
   ),
   "PT-1731 -r -a excludes the absolute column from aggregations",
) or diag($test_diff);

ok(
   no_diff(
      "$cmd -r -a --aggregations-position before -- cat $sample/pt-1731-in.txt",
      "t/pt-mext/samples/pt-1731-before-out.txt",
   ),
   "PT-1731 --aggregations-position before",
) or diag($test_diff);

like(
   `$cmd -a --aggregations-position middle -- cat $sample/pt-1731-in.txt 2>&1`,
   qr/Invalid --aggregations-position: middle/,
   "PT-1731 invalid --aggregations-position",
);

my $marker = "/tmp/pt-mext-pt-1731-marker.$$";
unlink $marker;
`$cmd -a --aggregations-position middle -- touch $marker 2>&1`;
ok(
   !-e $marker,
   "PT-1731 invalid --aggregations-position is rejected before running COMMAND",
);
unlink $marker;

ok(
   no_diff(
      "$cmd -r -a -- cat $sample/pt-1731-one-sample-in.txt",
      "t/pt-mext/samples/pt-1731-one-sample-out.txt",
   ),
   "PT-1731 -r -a with one sample has no aggregations",
) or diag($test_diff);

ok(
   no_diff(
      "$cmd -r -a -- cat $sample/pt-1731-wide-in.txt",
      "t/pt-mext/samples/pt-1731-wide-out.txt",
   ),
   "PT-1731 -r -a widens columns for wide negative deltas",
) or diag($test_diff);

# #############################################################################
# Done.
# #############################################################################
done_testing;
exit;
