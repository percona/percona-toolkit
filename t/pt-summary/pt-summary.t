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

my ($tool) = $PROGRAM_NAME =~ m/([\w-]+)\.t$/;

use Test::More tests => 2;

for my $i (2..3) {

   ok(
      no_diff(
         sub { print `$trunk/bin/pt-summary --read-samples "$trunk/t/pt-summary/samples/Linux/00$i/" | tail -n+3` },
         "t/pt-summary/samples/Linux/output_00$i.txt"),
      "--read-samples samples/Linux/00$i works"
   );
}

exit;
