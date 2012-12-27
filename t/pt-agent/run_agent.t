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
   print "interval=" . (defined $t ? $t : 'undef') . "\n";
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
      'check-interval' => "60",
   },
);

my $run0 = Percona::WebAPI::Resource::Run->new(
   number  => '0',
   program => 'pt-query-digest',
   options => '--output json',
   output  => 'spool',
);

my $svc0 = Percona::WebAPI::Resource::Service->new(
   name     => 'query-monitor',
   alias    => 'Query Monitor',
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

my $tmpdir = tempdir("/tmp/pt-agent.$PID.XXXXXX", CLEANUP => 1);
mkdir "$tmpdir/services" or die "Error making $tmpdir/services: $OS_ERROR";

my @ok_code = ();  # callbacks
my @oktorun = (1, 0);
my $oktorun = sub {
   my $ok = shift @oktorun;
   print "oktorun=" . (defined $ok ? $ok : 'undef') . "\n";
   my $code = shift @ok_code;
   $code->() if $code;
   return $ok
};

@wait = ();

$output = output(
   sub {
      pt_agent::run_agent(
         agent       => $agent,
         client      => $client,
         interval    => $interval,
         config_file => $config_file,
         lib_dir     => $tmpdir,
         oktorun     => $oktorun,  # optional, for testing
      );
   },
   stderr => 1,
);

is(
   `cat $config_file`,
   "api-key=123\ncheck-interval=60\n",
   "Write Config to config file"
); 

is(
   scalar @wait,
   1,
   "Called interval once"
);

is(
   $wait[0],
   60,
   "... used Config->options->check-interval"
);

ok(
   -f "$tmpdir/services/query-monitor",
   "Created services/query-monitor"
);

chomp(my $n_files = `ls -1 $tmpdir/services| wc -l | awk '{print \$1}'`);
is(
   $n_files,
   1,
   "... only created services/query-monitor"
);

ok(
   no_diff(
      "cat $tmpdir/services/query-monitor",
      "t/pt-agent/samples/service001",
   ),
   "query-monitor service file"
);

# Run run_agent() again, like the agent had been stopped and restarted.

$ua->{responses}->{get} = [
   # First check, fail
   {
      code    => 500,
   },
   # interval
   # 2nd check, init with latest Config and Services
   {
      headers => { 'X-Percona-Resource-Type' => 'Config' },
      content => as_hashref($config),
   },
   {
      headers => { 'X-Percona-Resource-Type' => 'Service' },
      content => [ as_hashref($svc0) ],
   },
   # interval
   # 3rd check, same Config and Services so nothing to do
   {
      headers => { 'X-Percona-Resource-Type' => 'Config' },
      content => as_hashref($config),
   },
   {
      headers => { 'X-Percona-Resource-Type' => 'Service' },
      content => [ as_hashref($svc0) ],
   },
   # interval, oktorun=0
];

# 0=while check, 1=after first check, 2=after 2nd check, etc.
@oktorun = (1, 1, 1, 0);

# Between the 2nd and 3rd checks, remove the config file (~/.pt-agent.conf)
# and query-monitor service  file.  When the tool re-GETs these, they'll be
# the same so it won't recreate them.  A bug here will cause these files to
# exist again after running.
$ok_code[2] = sub {
   unlink "$config_file";
   unlink "$tmpdir/services/query-monitor";
   Percona::Test::wait_until(sub { ! -f "$config_file" });
   Percona::Test::wait_until(sub { ! -f "$tmpdir/services/query-monitor" });
};

@wait = ();

$output = output(
   sub {
      pt_agent::run_agent(
         agent       => $agent,
         client      => $client,
         interval    => $interval,
         config_file => $config_file,
         lib_dir     => $tmpdir,
         oktorun     => $oktorun,  # optional, for testing
      );
   },
   stderr => 1,
);

is_deeply(
   \@wait,
   [ undef, 60, 60 ],
   "Got Config after error"
) or diag(Dumper(\@wait));

ok(
   ! -f "$config_file",
   "No Config diff, no config file change"
);

ok(
   ! -f "$tmpdir/services/query-monitor",
   "No Service diff, no service file changes"
);

# #############################################################################
# Done.
# #############################################################################
if ( -f $config_file ) {
   unlink $config_file 
      or warn "Error removing $config_file: $OS_ERROR";
}
done_testing;
