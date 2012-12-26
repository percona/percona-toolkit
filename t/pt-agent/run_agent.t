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
use JSON;

use Percona::Test;
use Percona::Test::Mock::UserAgent;
require "$trunk/bin/pt-agent";

Percona::Toolkit->import(qw(Dumper));
Percona::WebAPI::Representation->import(qw(as_hashref));

# #############################################################################
# Create mock client and Agent
# #############################################################################

# These aren't the real tests yet: to run_agent(), first we need
# a client and Agent, so create mock ones.

my $json = JSON->new;
$json->allow_blessed([]);
$json->convert_blessed([]);

my $ua = Percona::Test::Mock::UserAgent->new(
   encode => sub { my $c = shift; return $json->encode($c || {}) },
);

# Create cilent, get entry links
$ua->{responses}->{get} = [
   {
      content => {
         agents  => '/agents',
      },
   },
];

my $links = {
   agents   => '/agents',
   config   => '/agents/1/config',
   services => '/agents/1/services',
};

# Init agent, put Agent resource, return more links
$ua->{responses}->{put} = [
   {
      content => $links,
   },
];

my $client = eval {
   Percona::WebAPI::Client->new(
      api_key => '123',
      ua      => $ua,
   );
};
is(
   $EVAL_ERROR,
   '',
   'Create mock client'
) or die;

my @wait;
my $interval = sub {
   my $t = shift;
   push @wait, $t;
};

my $agent;
my $output = output(
   sub {
      $agent = pt_agent::init_agent(
         client   => $client,
         interval => $interval,
         agent_id => 1,
      );
   },
   stderr => 1,
);

my $have_agent = 1;

is_deeply(
   as_hashref($agent),
   {
      id       => '1',
      hostname => `hostname`,
      versions => {
         'Percona::WebAPI::Client' => "$Percona::WebAPI::Client::VERSION",
         'Perl'                    => sprintf '%vd', $PERL_VERSION,
      }
   },
   'Create mock Agent'
) or $have_agent = 0;

# Can't run_agent() without and agent.
if ( !$have_agent ) {
   diag(Dumper(as_hashref($agent)));
   die;
}

# #############################################################################
# Test run_agent()
# #############################################################################

# The agent does just basically 2 things: check for new config, and
# check for new services.  It doesn't do the latter until it has a
# config, because services require info from a config.  Config are
# written to $HOME/.pt-agent.conf; this can't be changed because the
# other processes (service runner and spool checker) must share the
# same config.

my $config = Percona::WebAPI::Resource::Config->new(
   options => {
      'check-interval' => 60,
   },
);

my $run0 = Percona::WebAPI::Resource::Run->new(
   number  => 0,
   program => 'pt-query-digest',
   options => '--output json',
   output  => 'spool',
);

my $svc0 = Percona::WebAPI::Resource::Service->new(
   name     => 'Query Monitor',
   schedule => '...',
   runs     => [ $run0 ],
);

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Config' },
      content => as_hashref($config),
   },
   {
      headers => { 'X-Percona-Resource-Type' => 'Service' },
      content => [ as_hashref($svc0) ],
   },
];

# The only thing pt-agent must have is the API key in the config file,
# everything else relies on defaults until the first Config is gotten
# from Percona. -- The tool calls init_config_file() if the file doesn't
# exist, so we do the same.  Might as well test it while we're here.
my $config_file = pt_agent::get_config_file();
unlink $config_file if -f $config_file;
pt_agent::init_config_file(file => $config_file, api_key => '123');

is(
   `cat $config_file`,
   "api-key=123\n",
   "init_config_file()"
);

@wait = ();
$interval = sub {
   my $t = shift;
   push @wait, $t;
   pt_agent::_err('interval');
};

#$output = output(
#   sub {
      pt_agent::run_agent(
         agent       => $agent,
         client      => $client,
         interval    => $interval,
         config_file => $config_file,
      );
#   },
#   stderr => 1,
#);
#print $output;

# #############################################################################
# Done.
# #############################################################################
done_testing;
