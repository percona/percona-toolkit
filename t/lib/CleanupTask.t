#!/usr/bin/perl

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
use CleanupTask;

my $foo = 0;
{
   my $set_foo = new CleanupTask(sub { $foo = 42; });
   is(
      $foo,
      0,
      "Cleanup task not called yet"
   );
}

is(
   $foo,
   42,
   "Cleanup task called after obj destroyed"
);

# #############################################################################
# Done.
# #############################################################################
exit;
