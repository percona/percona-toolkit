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

use PerconaTest;
use Percona::Toolkit;
use Percona::WebAPI::Resource::Config;
use Percona::WebAPI::Util qw(resource_diff);

my $x = Percona::WebAPI::Resource::Config->new(
   ts      => '100',
   name    => 'Default',
   options => {
      'lib'   => '/var/lib',
      'spool' => '/var/spool',
   },
);

my $y = Percona::WebAPI::Resource::Config->new(
   ts      => '100',
   name    => 'Default',
   options => {
      'lib'   => '/var/lib',
      'spool' => '/var/spool',
   },
);

is(
   resource_diff($x, $y),
   0,
   "No diff"
);

$y->options->{spool} = '/var/lib/spool';

is(
   resource_diff($x, $y),
   1,
   "Diff"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
