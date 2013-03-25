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

# Running the agent is going to cause it to schedule the services,
# i.e. write a real crontab.  The test box/user shouldn't have a
# crontab, so we'll warn and clobber it if there is one.
my $crontab = `crontab -l 2>/dev/null`;
if ( $crontab ) {
   warn "Removing crontab: $crontab\n";
   `crontab -r`;
}

# #############################################################################
# Create mock client and Agent
# #############################################################################

# These aren't the real tests yet: to run_agent, first we need
# a client and Agent, so create mock ones.

my $output;
my $json = JSON->new->canonical([1])->pretty;
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
   'Create mock client'
) or die;

my $agent = Percona::WebAPI::Resource::Agent->new(
   id       => '123',
   hostname => 'host',
   links    => {
      self   => '/agents/123',
      config => '/agents/123/config',
   },
);

my @wait;
my $interval = sub {
   my $t = shift;
   push @wait, $t;
   print "interval=" . (defined $t ? $t : 'undef') . "\n";
};

# #############################################################################
# Test run_agent
# #############################################################################

# The agent does just basically 2 things: check for new config, and
# check for new services.  It doesn't do the latter until it has a
# config, because services require info from a config.  Config are
# written to $HOME/.pt-agent.conf; this can't be changed because the
# other processes (service runner and spool checker) must share the
# same config.

my $config = Percona::WebAPI::Resource::Config->new(
   ts      => 1363720060,
   name    => 'Default',
   options => {
      'check-interval' => "60",
   },
   links   => {
      self     => '/agents/123/config',
      services => '/agents/123/services',
   },
);

my $run0 = Percona::WebAPI::Resource::Task->new(
   name    => 'query-history',
   number  => '0',
   program => 'pt-query-digest',
   options => '--output json',
   output  => 'spool',
);

my $svc0 = Percona::WebAPI::Resource::Service->new(
   name           => 'query-history',
   run_schedule   => '1 * * * *',
   spool_schedule => '2 * * * *',
   tasks          => [ $run0 ],
   links          => {
      self => '/query-history',
      data => '/query-history/data',
   },
);

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Config' },
      content => as_hashref($config, with_links => 1),
   },
   {
      headers => { 'X-Percona-Resource-Type' => 'Service' },
      content => [ as_hashref($svc0, with_links => 1) ],
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

my $tmpdir = tempdir("/tmp/pt-agent.$PID.XXXXXX", CLEANUP => 0);
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
         json        => $json,     # optional, for testing
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
   -f "$tmpdir/services/query-history",
   "Created services/query-history"
) or diag($output);

chomp(my $n_files = `ls -1 $tmpdir/services| wc -l | awk '{print \$1}'`);
is(
   $n_files,
   1,
   "... only created services/query-history"
);

ok(
   no_diff(
      "cat $tmpdir/services/query-history",
      "t/pt-agent/samples/service001",
   ),
   "query-history service file"
);

$crontab = `crontab -l 2>/dev/null`;
like(
   $crontab,
   qr/pt-agent --run-service query-history$/m,
   "Scheduled --run-service with crontab"
);

like(
   $crontab,
   qr/pt-agent --send-data query-history$/m,
   "Scheduled --send-data with crontab"
);

# #############################################################################
# Run run_agent again, like the agent had been stopped and restarted.
# #############################################################################

$ua->{responses}->{get} = [
   # First check, fail
   {
      code    => 500,
   },
   # interval
   # 2nd check, init with latest Config and Services
   {
      headers => { 'X-Percona-Resource-Type' => 'Config' },
      content => as_hashref($config, with_links => 1),
   },
   {
      headers => { 'X-Percona-Resource-Type' => 'Service' },
      content => [ as_hashref($svc0, with_links => 1) ],
   },
   # interval
   # 3rd check, same Config and Services so nothing to do
   {
      headers => { 'X-Percona-Resource-Type' => 'Config' },
      content => as_hashref($config, with_links => 1),
   },
   {
      headers => { 'X-Percona-Resource-Type' => 'Service' },
      content => [ as_hashref($svc0, with_links => 1) ],
   },
   # interval, oktorun=0
];

# 0=while check, 1=after first check, 2=after 2nd check, etc.
@oktorun = (1, 1, 1, 0);

# Between the 2nd and 3rd checks, remove the config file (~/.pt-agent.conf)
# and query-history service  file.  When the tool re-GETs these, they'll be
# the same so it won't recreate them.  A bug here will cause these files to
# exist again after running.
$ok_code[2] = sub {
   unlink "$config_file";
   unlink "$tmpdir/services/query-history";
   Percona::Test::wait_until(sub { ! -f "$config_file" });
   Percona::Test::wait_until(sub { ! -f "$tmpdir/services/query-history" });
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
         json        => $json,     # optional, for testing
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
   ! -f "$tmpdir/services/query-history",
   "No Service diff, no service file changes"
);

my $new_crontab = `crontab -l 2>/dev/null`;
is(
   $new_crontab,
   $crontab,
   "Crontab is the same"
);

# #############################################################################
# Test a run_once_on_start service
# #############################################################################

diag(`rm -f $tmpdir/* >/dev/null 2>&1`);
diag(`rm -rf $tmpdir/services/*`);
mkdir "$tmpdir/spool" or die $OS_ERROR;

$config_file = pt_agent::get_config_file();
unlink $config_file if -f $config_file;
pt_agent::init_config_file(file => $config_file, api_key => '123');

$config = Percona::WebAPI::Resource::Config->new(
   ts      => 1363720060,
   name    => 'Test run_once_on_start',
   options => {
      'check-interval' => "60",
      'lib'            => $tmpdir,
      'spool'          => "$tmpdir/spool",
      'pid'            => "$tmpdir/pid",
      'log'            => "$tmpdir/log"
   },
   links   => {
      self     => '/agents/123/config',
      services => '/agents/123/services',
   },
);

$run0 = Percona::WebAPI::Resource::Task->new(
   name    => 'run-at-start',
   number  => '0',
   program => 'date',
   output  => 'spool',
);

$svc0 = Percona::WebAPI::Resource::Service->new(
   name              => 'test-run-at-start',
   run_schedule      => '0 0 1 1 *',
   spool_schedule    => '0 0 1 1 *',
   run_once_on_start => 1,  # here's the magic
   tasks             => [ $run0 ],
   links             => {
      self => '/query-history',
      data => '/query-history/data',
   },
);

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Config' },
      content => as_hashref($config, with_links => 1),
   },
   {
      headers => { 'X-Percona-Resource-Type' => 'Service' },
      content => [ as_hashref($svc0, with_links => 1) ],
   },
   {
      headers => { 'X-Percona-Resource-Type' => 'Config' },
      content => as_hashref($config, with_links => 1),
   },
   {
      headers => { 'X-Percona-Resource-Type' => 'Service' },
      content => [ as_hashref($svc0, with_links => 1) ],
   },
];

@ok_code = ();  # callbacks
@oktorun = (1, 1, 0);
@wait    = ();

$output = output(
   sub {
      pt_agent::run_agent(
         agent       => $agent,
         client      => $client,
         interval    => $interval,
         config_file => $config_file,
         lib_dir     => $tmpdir,
         oktorun     => $oktorun,       # optional, for testing
         json        => $json,          # optional, for testing
         bin_dir     => "$trunk/bin/",  # optional, for testing
      );
   },
   stderr => 1,
);

Percona::Test::wait_for_files("$tmpdir/spool/test-run-at-start");

like(
   $output,
   qr/Starting test-run-at-start service/,
   "Ran service on start"
);

my @runs = $output =~ m/Starting test-run-at-start service/g;

is(
   scalar @runs,
   1,
   "... only ran it once"
);

chomp($output = `cat $tmpdir/spool/test-run-at-start 2>/dev/null`);
ok(
   $output,
   "... service ran at start"
) or diag($output);

chomp($output = `crontab -l`);
like(
   $output,
   qr/--run-service test-run-at-start/,
   "... service was scheduled"
);

# #############################################################################
# Done.
# #############################################################################

# This shouldn't cause an error, but if it does, let it show up
# in the results as an error.
`crontab -r`;

if ( -f $config_file ) {
   unlink $config_file 
      or warn "Error removing $config_file: $OS_ERROR";
}

done_testing;
