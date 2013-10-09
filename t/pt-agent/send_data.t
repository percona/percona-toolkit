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

Percona::Toolkit->import(qw(Dumper have_required_args));
Percona::WebAPI::Representation->import(qw(as_hashref));

my @log;
my $logger = Percona::Test::Mock::AgentLogger->new(log => \@log);
pt_agent::_logger($logger);

my $sample = "t/pt-agent/samples";

# #############################################################################
# Create mock client and Agent
# #############################################################################

# These aren't the real tests yet: to run_agent(), first we need
# a client and Agent, so create mock ones.

my $json = JSON->new->canonical([1])->pretty;
$json->allow_blessed([]);
$json->convert_blessed([]);

my $ua = Percona::Test::Mock::UserAgent->new(
   encode => sub { my $c = shift; return $json->encode($c || {}) },
);

# Create cilent, get entry links
my $links = {
   agents          => '/agents',
   config          => '/agents/1/config',
   services        => '/agents/1/services',
   'query-history' => '/query-history',
};

$ua->{responses}->{get} = [
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

my $agent = Percona::WebAPI::Resource::Agent->new(
   uuid     => '123',
   hostname => 'prod1', 
   links    => $links,
);

is_deeply(
   as_hashref($agent),
   {
      uuid     => '123',
      hostname => 'prod1',
   },
   'Create mock Agent'
) or die;

# #############################################################################
# Test send_data
# #############################################################################

my $tmpdir = tempdir("/tmp/pt-agent.$PID.XXXXXX", CLEANUP => 1);
pt_agent::init_lib_dir(
   lib_dir => $tmpdir,
   quiet   => 1,
);
pt_agent::init_spool_dir(
   spool_dir => $tmpdir,
   service   => 'query-history',
   quiet     => 1,
); 

`cp $trunk/$sample/query-history/data001.json $tmpdir/query-history/1.data001.data`;
`cp $trunk/$sample/service001 $tmpdir/services/query-history`;

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Agent' },
      content => as_hashref($agent, with_links => 1),
   },
];

$ua->{responses}->{post} = [
   {
      content => $links,
   },
];

my $output = output(
   sub {
      pt_agent::send_data(
         api_key   => '123',
         service   => 'query-history',
         lib_dir   => $tmpdir,
         spool_dir => $tmpdir,
         # optional, for testing:
         client      => $client,
         entry_links => $links,
         agent       => $agent,
         log_file    => "$tmpdir/log",
         json        => $json,
         delay       => 0,
      ),
   },
);

is(
   scalar @{$client->ua->{content}->{post}},
   1,
   "Only sent 1 resource"
) or diag(
   $output,
   Dumper($client->ua->{content}->{post}),
   `cat $tmpdir/logs/query-history.send`
);

is_deeply(
   $ua->{requests},
   [
      'GET /agents/123',
      'POST /query-history/data',
   ],
   "POST to Service.links.data"
);

ok(
   no_diff(
      $client->ua->{content}->{post}->[0] || '',
      "$sample/query-history/data001.send",
      cmd_output => 1,
   ),
   "Sent data file as multi-part resource (query-history/data001)"
) or diag(Dumper($client->ua->{content}->{post}));

ok(
   !-f "$tmpdir/query-history/1.data001.data",
   "Removed data file after sending successfully"
);

is(
   $ua->{request_objs}->[-1]->header('content-type'),
   'multipart/form-data; boundary=Ym91bmRhcnk',
   'Content-Type=multipart/form-data; boundary=Ym91bmRhcnk'
) or diag(Dumper($ua));

# #############################################################################
# Error 400 on send
# #############################################################################

@log = ();
$client->ua->{content}->{post} = [];
$ua->{requests} = [];

`cp $trunk/$sample/query-history/data001.json $tmpdir/query-history/1.data001.data`;

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Agent' },
      content => as_hashref($agent, with_links => 1),
   },
];

$ua->{responses}->{post} = [
   {
      code    => 400,
      content => '',
   },
];

$output = output(
   sub {
      pt_agent::send_data(
         api_key   => '123',
         service   => 'query-history',
         lib_dir   => $tmpdir,
         spool_dir => $tmpdir,
         # optional, for testing:
         client      => $client,
         entry_links => $links,
         agent       => $agent,
         log_file    => "$tmpdir/log",
         json        => $json,
         delay       => 0,
      ),
   },
);

is(
   scalar @{$client->ua->{content}->{post}},
   1,
   "400: sent resource"
) or diag(
   $output,
   Dumper($client->ua->{content}->{post}),
   `cat $tmpdir/logs/query-history.send`
);

ok(
   -f "$tmpdir/query-history/1.data001.data",
   "400: file not removed"
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
done_testing;
