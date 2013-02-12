#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;
use lib "$ENV{PERCONA_TOOLKIT_BRANCH}/t/lib/Lmo";

{ package Clean; use Foo; }

is_deeply([ @Clean::ISA ], [], "Didn't mess with caller's ISA");
is(Clean->can('has'), undef, "Didn't export anything");

done_testing;
