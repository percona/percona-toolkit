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

my $ua = Percona::Test::Mock::UserAgent->new(
   encode => sub { my $c = shift; return encode_json($c || {}) },
);

# When Percona::WebAPI::Client is created, it gets its base_url,
# to get the API's entry links.
$ua->{responses}->{get} = [
   {
      content => {
         agents  => '/agents',
      },
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
   'Create Client with mock user agent'
) or die;

# #############################################################################
# Init a new agent, i.e. create it.
# #############################################################################

# Since we're passing agent_id, the tool will call its get_uuid()
# and POST an Agent resource to the fake ^ agents links.  It then
# expects config and services links.

$ua->{responses}->{post} = [
   {
      content => {
         agents   => '/agents',
         config   => '/agents/123/config',
         services => '/agents/123/services',
      },
   },
];

# interval is a callback that subs call to sleep between failed
# client requests.  We're not faking a client request failure,
# so @wait should stay empty.
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
      );
   },
   stderr => 1,
);

is_deeply(
   as_hashref($agent),
   {
      id       => '123',
      hostname => `hostname`,
      versions => {
         'Percona::WebAPI::Client' => "$Percona::WebAPI::Client::VERSION",
         'Perl'                    => sprintf('%vd', $PERL_VERSION),
      }
   },
   'Create new Agent'
) or diag(Dumper(as_hashref($agent)));

is(
   scalar @wait,
   0,
   "Client did not wait (new Agent)"
);

is_deeply(
   $client->links,
   {
      agents   => '/agents',
      config   => '/agents/123/config',
      services => '/agents/123/services',
   },
   "Client got new links"
) or diag(Dumper($client->links));

# Repeat this test but this time fake an error, so the tool isn't
# able to create the Agent first time, so it should wait (call
# interval), and try again.

$ua->{responses}->{post} = [
   {  # 1, the fake error
      code => 500,  
   },
      # 2, code should call interval
   {  # 3, code should try again, then receive this
      content => {
         agents   => '/agents',
         config   => '/agents/456/config',
         services => '/agents/456/services',
      },
   },
];

@wait = ();

$output = output(
   sub {
      $agent = pt_agent::init_agent(
         client   => $client,
         interval => $interval,
      );
   },
   stderr => 1,
);

is_deeply(
   as_hashref($agent),
   {
      id       => '123',
      hostname => `hostname`,
      versions => {
         'Percona::WebAPI::Client' => "$Percona::WebAPI::Client::VERSION",
         'Perl'                    => sprintf '%vd', $PERL_VERSION,
      }
   },
   'Create new Agent after error'
) or diag(Dumper(as_hashref($agent)));

is(
   scalar @wait,
   1,
   "Client waited"
);

like(
   $output,
   qr{WARNING Failed to POST /agents},
   "POST /agents failure logged"
);

# #############################################################################
# Init an existing agent, i.e. update it.
# #############################################################################

# When agent_id is passed to init_agent(), the tool does PUT Agent
# to tell Percona that the Agent has come online again, and to update
# the agent's versions.

$ua->{responses}->{put} = [
   {
      content => {
         agents   => '/agents',
         config   => '/agents/999/config',
         services => '/agents/999/services',
      },
   },
];

@wait = ();

$output = output(
   sub {
      $agent = pt_agent::init_agent(
         client   => $client,
         interval => $interval,
         agent_id => '999',
      );
   },
   stderr => 1,
);

is_deeply(
   as_hashref($agent),
   {
      id       => '999',
      hostname => `hostname`,
      versions => {
         'Percona::WebAPI::Client' => "$Percona::WebAPI::Client::VERSION",
         'Perl'                    => sprintf '%vd', $PERL_VERSION,
      }
   },
   'Update old Agent'
) or diag(Dumper(as_hashref($agent)));

is(
   scalar @wait,
   0,
   "Client did not wait (old Agent)"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
