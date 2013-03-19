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
require "$trunk/bin/pt-agent";

Percona::Toolkit->import(qw(Dumper));
Percona::WebAPI::Representation->import(qw(as_hashref));

my $tmpdir = tempdir("/tmp/pt-agent.$PID.XXXXXX", CLEANUP => 1);

my $ua = Percona::Test::Mock::UserAgent->new(
   encode => sub { my $c = shift; return encode_json($c || {}) },
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

# #############################################################################
# Init a new agent, i.e. create it.
# #############################################################################

my $return_agent = {
   uuid     => '123',
   hostname => `hostname`,
   versions => {
      'Percona::WebAPI::Client' => "$Percona::WebAPI::Client::VERSION",
      'Perl'                    => sprintf('%vd', $PERL_VERSION),
   },
   links    => {
      self   => '/agents/123',
      config => '/agents/123/config',
   },
};

$ua->{responses}->{post} = [
   {
      headers => { 'Location' => '/agents/123' },
   },
];

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Agent' },
      content => $return_agent,
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
         client      => $client,
         interval    => $interval,
         agents_link => "/agents",
         lib_dir     => $tmpdir,
      );
   },
   stderr => 1,
);

is_deeply(
   as_hashref($agent, with_links => 1),
   $return_agent,
   'Create new Agent'
) or diag($output, Dumper(as_hashref($agent, with_links => 1)));

is(
   scalar @wait,
   0,
   "Client did not wait (new Agent)"
) or diag($output);

# The tool should immediately write the Agent to --lib/agent.
ok(
   -f "$tmpdir/agent",
   "Wrote Agent to --lib/agent"
) or diag($output);

# From above, we return an Agent with id=123.  Check that this
# is what the tool actually wrote.
$output = `cat $tmpdir/agent 2>/dev/null`;
like(
   $output,
   qr/"uuid":"123"/,
   "Saved new Agent"
) or diag($output);

# Repeat this test but this time fake an error, so the tool isn't
# able to create the Agent first time, so it should wait (call
# interval), and try again.

unlink "$tmpdir/agent" if -f "$tmpdir/agent";

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
      content => $return_agent,
   },
];

@wait = ();
$ua->{requests} = [];

$output = output(
   sub {
      $agent = pt_agent::init_agent(
         client      => $client,
         interval    => $interval,
         agents_link => '/agents',
         lib_dir     => $tmpdir,
      );
   },
   stderr => 1,
);

is_deeply(
   as_hashref($agent, with_links => 1),
   $return_agent,
   'Create new Agent after error'
) or diag(Dumper(as_hashref($agent, with_links => 1)));

is(
   scalar @wait,
   1,
   "Client waited"
);

is_deeply(
   $ua->{requests},
   [
      'POST /agents',     # first attempt, 500 error
      'POST /agents',     # second attemp, 200 OK
      'GET /agents/456',  # GET new Agent
   ],
   "POST POST GET new Agent"
) or diag(Dumper($ua->{requests}));

like(
   $output,
   qr{WARNING Failed to POST /agents},
   "POST /agents failure logged"
);

ok(
   -f "$tmpdir/agent",
   "Wrote Agent to --lib/agent again"
);

$output = `cat $tmpdir/agent 2>/dev/null`;
like(
   $output,
   qr/"id":"456"/,
   "Saved new Agent again"
) or diag($output);

# Do not remove lib/agent; the next test will use it.

# #############################################################################
# Init an existing agent, i.e. update it.
# #############################################################################

# If --lib/agent exists, the tool should create an Agent obj from it
# then attempt to PUT it to the agents link.  The previous tests should
# have left an Agent file with id=456.

my $hashref = decode_json(pt_agent::slurp("$tmpdir/agent"));
my $saved_agent = Percona::WebAPI::Resource::Agent->new(%$hashref);

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
      content => $return_agent,
   }
];

@wait = ();
$ua->{requests} = [];

$output = output(
   sub {
      $agent = pt_agent::init_agent(
         client      => $client,
         interval    => $interval,
         agents_link => '/agents',
         lib_dir     => $tmpdir,
      );
   },
   stderr => 1,
);

is_deeply(
   as_hashref($agent),
   as_hashref($saved_agent),
   'Used saved Agent'
) or diag($output, Dumper(as_hashref($agent)));

like(
   $output,
   qr/Reading saved Agent from $tmpdir\/agent/,
   "Reports reading saved Agent"
) or diag($output);

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
   "PUT then GET saved Agent"
) or diag(Dumper($ua->{requests}));

# #############################################################################
# Done.
# #############################################################################
done_testing;
