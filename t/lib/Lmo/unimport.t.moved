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

{
   package One; use Lmo;
   has one => (is => 'ro', default => sub { 'one' });
   no Lmo;
}

my $unimported = One->new();
is
   $unimported->one(),
   'one',
   "after unimporting, ->one still works";

ok !$unimported->can($_), "after unimpoirt, can't $_" for qw(has with extends);

done_testing;
