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
use Percona::WebAPI::Resource::Agent;
use Percona::WebAPI::Resource::Config;
use Percona::WebAPI::Representation;

my $agent = Percona::WebAPI::Resource::Agent->new(
   id       => '123',
   hostname => 'pt',
   versions => {
      Perl => '5.10.1',
   },
);

is(
   Percona::WebAPI::Representation::as_json($agent),
   q/{"versions":{"Perl":"5.10.1"},"id":"123","hostname":"pt"}/,
   "as_json"
);

my $config = Percona::WebAPI::Resource::Config->new(
   ts      => '100',
   name    => 'Default',
   options => {
      'check-interval' => 60,
   },
);

is(
   Percona::WebAPI::Representation::as_config($config),
   "check-interval=60\n",
   "as_config"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
