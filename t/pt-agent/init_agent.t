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
   encode => sub { return encode_json(shift) },
);

# When Percona::WebAPI::Client is created, it gets its base_url,
# to get the API's entry links.
$ua->{responses}->{get} = [
   {
      content => {
         links => {
            agents  => '/agents',
         },
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
         links => {
            agents   => '/agents',
            config   => '/agents/123/config',
            services => '/agents/123/services',
         },
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
         'Perl'                    => sprintf '%vd', $PERL_VERSION,
      }
   },
   'Create new Agent'
) or diag(Dumper(as_hashref($agent)));

is(
   scalar @wait,
   0,
   "Client did not wait"
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

# #############################################################################
# Done.
# #############################################################################
done_testing;
