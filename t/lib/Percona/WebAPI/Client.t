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
use File::Temp qw(tempdir);

use Percona::Test;
use Percona::Test::Mock::UserAgent;
use Percona::WebAPI::Client;
use Percona::WebAPI::Resource::Agent;
use Percona::WebAPI::Resource::Config;
use Percona::WebAPI::Resource::Service;
use Percona::WebAPI::Resource::Task;

Percona::Toolkit->import(qw(Dumper have_required_args));
Percona::WebAPI::Representation->import(qw(as_json as_hashref));

# #############################################################################
# Create a client with a mock user-agent.
# #############################################################################

my $json = JSON->new;
$json->allow_blessed([]);
$json->convert_blessed([]);

my $ua = Percona::Test::Mock::UserAgent->new(
   encode => sub { my $c = shift; return $json->encode($c || {}) },
);

my $client = eval {
   Percona::WebAPI::Client->new(
      api_key => '123',
      ua      => $ua,
   );
};

is(
   $EVAL_ERROR,
   '',
   'Create client'
) or die;

# #############################################################################
# First thing a client should do is get the entry links.
# #############################################################################

my $return_links = {  # what the server returns
   agents => '/agents',
};

$ua->{responses}->{get} = [
   {
      content => {
         links => $return_links,
      }
   },
];

my $links = $client->get(link => $client->entry_link);

is_deeply(
   $links,
   $return_links,
   "Get entry links"
) or diag(Dumper($links));

is_deeply(
   $ua->{requests},
   [
      'GET https://cloud-api.percona.com',
   ],
   "1 request, 1 GET"
) or diag(Dumper($ua->{requests}));


# #############################################################################
# Second, a new client will POST an Agent for itself.  The entry links
# should have an "agents" link.  The server response is empty but the
# URI for the new Agent resource is given by the Location header.
# #############################################################################

my $agent = Percona::WebAPI::Resource::Agent->new(
   id       => '123',
   hostname => 'host',
);

$ua->{responses}->{post} = [
   {
      headers => { 'Location' => 'agents/5' },
      content => '',
   },
];

my $uri = $client->post(resources => $agent, link => $links->{agents});

is(
   $uri,
   "agents/5",
   "POST Agent, got Location URI"
);

# #############################################################################
# After successfully creating the new Agent, the client should fetch
# the new Agent resoruce which will have links to the next step: the
# agent's config.
# #############################################################################

$return_links = {
   self   => 'agents/5',
   config => 'agents/5/config',
};

my $content = {
   %{ as_hashref($agent) },
   links => $return_links,
};

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Agent' },
      content => $content,
   },
];

# Re-using $agent, i.e. updating it with the actual, newly created
# Agent resource as returned by the server with links.
$agent = $client->get(link => $uri);

# Need to use with_links=>1 here because by as_hashref() removes
# links by default because it's usually used to encode and send
# resources, and clients never send links; but here we're using
# it for testing.
is_deeply(
   as_hashref($agent, with_links => 1),
   $content,
   "GET Agent with links"
) or diag(Dumper(as_hashref($agent, with_links => 1)));

# #############################################################################
# Now the agent can get its Config.
# #############################################################################

$return_links = {
   self     => 'agents/5/config',
   services => 'agents/5/services',
};

my $return_config = Percona::WebAPI::Resource::Config->new(
   ts      => '100',
   name    => 'Default',
   options => {},
   links   => $return_links,
);

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Config' },
      content => as_hashref($return_config, with_links => 1),
   },
];

my $config = $client->get(link => $agent->links->{config});

is_deeply(
   as_hashref($config, with_links => 1),
   as_hashref($return_config, with_links => 1), 
   "GET Config"
) or diag(Dumper(as_hashref($config, with_links => 1)));

# #############################################################################
# Once an agent is configured, i.e. successfully gets a Config resource,
# its Config should have a services link which returns a list of Service
# resources, each with their own links.
# #############################################################################

$return_links = {
   'send_data' => '/query-monitor',
};

my $run0 = Percona::WebAPI::Resource::Task->new(
   name    => 'run-pqd',
   number  => '0',
   program => 'pt-query-digest',
   options => '--output json',
   output  => 'spool',
);

my $svc0 = Percona::WebAPI::Resource::Service->new(
   ts             => '123',
   name           => 'query-monitor',
   run_schedule   => '1 * * * *',
   spool_schedule => '2 * * * *',
   tasks          => [ $run0 ],
   links          => $return_links,
);

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Service' },
      content => [ as_hashref($svc0, with_links => 1) ],
   },
];

my $services = $client->get(link => $config->links->{services});

is(
   scalar @$services,
   1,
   "Got 1 service"
);

is_deeply(
   as_hashref($services->[0], with_links => 1),
   as_hashref($svc0, with_links => 1),
   "GET Services"
) or diag(Dumper(as_hashref($services, with_links => 1)));

is(
   $services->[0]->links->{send_data},
   "/query-monitor",
   "send_data link for Service"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
