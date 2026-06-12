#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use PerconaTest;
use Test::More;

my $sample = "$trunk/t/pt-pmp/samples/stacktrace001.in";

ok(
   no_diff(
      "$trunk/bin/pt-pmp -t ^25 $sample",
      "t/pt-pmp/samples/stacktrace001_t25.out",
   ),
   '-t ^25 prints stack traces for threads those numbers start from 25'
) or diag($test_diff);

ok(
   no_diff(
      "$trunk/bin/pt-pmp -t 21201,23846 $sample",
      "t/pt-pmp/samples/stacktrace001_t21201_23846.out",
   ),
   '-t 21201,23846 prints stack traces for threads 21201,23846'
) or diag($test_diff);

ok(
   no_diff(
      "$trunk/bin/pt-pmp -t 21201,237.8 $sample",
      "t/pt-pmp/samples/stacktrace001_t21201_237_8.out",
   ),
   '-t 21201,237.8 prints stack traces for threads 21201, 23798, 23728'
) or diag($test_diff);

done_testing;
