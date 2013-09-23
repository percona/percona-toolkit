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
use Percona::Test::Mock::AgentLogger;
require "$trunk/bin/pt-agent";

Percona::Toolkit->import(qw(Dumper));
Percona::WebAPI::Representation->import(qw(as_hashref));

my $tmpdir = tempdir("/tmp/pt-agent.$PID.XXXXXX", CLEANUP => 1);

my $json = JSON->new->canonical([1])->pretty;
$json->allow_blessed([]);
$json->convert_blessed([]);

my @log;
my $logger = Percona::Test::Mock::AgentLogger->new(log => \@log);
pt_agent::_logger($logger);

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
   'Create Client with mock user agent'
) or die;

my @ok;
my $oktorun = sub {
   return shift @ok;
};

my @wait;
my $interval = sub {
   my $t = shift;
   push @wait, $t;
};

# #############################################################################
# Init a new agent, i.e. create it.
# #############################################################################

my $post_agent = Percona::WebAPI::Resource::Agent->new(
   uuid     => '123',
   hostname => 'host1',
   username => 'name1',
   versions => {
   },
   links    => {
      self   => '/agents/123',
      config => '/agents/123/config',
   },
);

my $return_agent = Percona::WebAPI::Resource::Agent->new(
   uuid     => '123',
   hostname => 'host2',
   username => 'name2',
   versions => {
   },
   links    => {
      self   => '/agents/123',
      config => '/agents/123/config',
   },
);

$ua->{responses}->{post} = [
   {
      headers => { 'Location' => '/agents/123' },
   },
];

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Agent' },
      content => as_hashref($return_agent, with_links =>1 ),
   },
];

my $got_agent;
my $output = output(
   sub {
      ($got_agent) = pt_agent::init_agent(
         agent    => $post_agent,
         action   => 'post',
         link     => "/agents",
         client   => $client,
         interval => $interval,
         tries    => 4,
      );
   },
   stderr => 1,
);

is(
   $got_agent->hostname,
   'host2',
   'Got and returned Agent'
) or diag($output, Dumper(as_hashref($got_agent, with_links => 1)));

is(
   scalar @wait,
   0,
   "Client did not wait (new Agent)"
) or diag($output);

# #############################################################################
# Repeat this test but this time fake an error, so the tool isn't able
# to create the Agent first time, so it should wait (call interval),
# and try again.
# #############################################################################

$return_agent->{id}    = '456';
$return_agent->{links} = {
   self   => '/agents/456',
   config => '/agents/456/config',
};

$ua->{responses}->{post} = [
   {  # 1, the fake error
      code => 500,  
   },
      # 2, code should call interval
   {  # 3, code should try again, then receive this
      code    => 200,
      headers => { 'Location' => '/agents/456' },
   },
];
      # 4, code will GET the new Agent
$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Agent' },
      content => as_hashref($return_agent, with_links =>1 ),
   },
];

@ok   = qw(1 1 0);
@wait = ();
@log  = ();                     
$ua->{requests} = [];

$output = output(
   sub {
      ($got_agent) = pt_agent::init_agent(
         agent    => $post_agent,
         action   => 'post',
         link     => "/agents",
         client   => $client,
         interval => $interval,
         tries    => 5,
         oktorun  => $oktorun,
      );
   },
   stderr => 1,
);

is(
   ($got_agent ? $got_agent->hostname : ''),
   'host2',
   'Got and returned Agent after error'
) or diag($output, Dumper($got_agent));

is(
   scalar @wait,
   1,
   "Client waited after error"
);

is_deeply(
   $ua->{requests},
   [
      'POST /agents',     # first attempt, 500 error
      'POST /agents',     # second attemp, 200 OK
      'GET /agents/456',  # GET new Agent
   ],
   "POST POST GET new Agent after error"
) or diag(Dumper($ua->{requests}));

like(
   $log[1],
   qr{WARNING Failed to POST /agents},
   "POST /agents failure logged after error"
) or diag(Dumper($ua->{requests}), Dumper(\@log));

# #############################################################################
# Init an existing agent, i.e. update it.
# #############################################################################

my $put_agent = Percona::WebAPI::Resource::Agent->new(
   uuid     => '123',
   hostname => 'host3',
   username => 'name3',
   versions => {
   },
   links    => {
      self   => '/agents/123',
      config => '/agents/123/config',
   },
);

$ua->{responses}->{put} = [
   {
      code    => 200,
      headers => {
         Location => '/agents/123',
      },
   },
];
$ua->{responses}->{get} = [
   {
      code    => 200,
      headers => { 'X-Percona-Resource-Type' => 'Agent' },
      content => as_hashref($return_agent, with_links =>1 ),
   }
];

@wait = ();
$ua->{requests} = [];

$output = output(
   sub {
      ($got_agent) = pt_agent::init_agent(
         agent    => $put_agent,
         action   => 'put',
         link     => "/agents/123",
         client   => $client,
         interval => $interval,
         tries    => 4,
      );
   },
   stderr => 1,
);

is(
   $got_agent->hostname,
   'host2',
   'PUT Agent'
) or diag($output, Dumper(as_hashref($got_agent, with_links => 1)));

is(
   scalar @wait,
   0,
   "Client did not wait (saved Agent)"
);

is_deeply(
   $ua->{requests},
   [
      'PUT /agents/123',
      'GET /agents/123',
   ],
   "PUT then GET Agent"
) or diag(Dumper($ua->{requests}));

# #############################################################################
# Status 403 (too many agents) should abort further attempts.
# #############################################################################

$ua->{responses}->{post} = [
   {  # 1, the fake error
      code => 403,  
   },
];

@ok   = qw(1 1 0);
@wait = ();
@log  = ();
$ua->{requests} = [];

$output = output(
   sub {
      ($got_agent) = pt_agent::init_agent(
         agent    => $post_agent,
         action   => 'post',
         link     => "/agents",
         client   => $client,
         interval => $interval,
         tries    => 3,
         oktorun  => $oktorun,
      );
   },
   stderr => 1,
);

is(
   scalar @wait,
   2,
   "Too many agents (403): waits"
);

is_deeply(
   $ua->{requests},
   [
      'POST /agents',
      'POST /agents',
   ],
   "Too many agents (403): tries"
) or diag(Dumper($ua->{requests}));

my $n = grep { $_ =~ m/too many agents/ } @log;
is(
   $n,
   1,
   "Too many agents (403): does not repeat warning"
) or diag(Dumper(\@log));

# #############################################################################
# Done.
# #############################################################################
done_testing;
