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

plan skip_all => "Need to make start-service testable";

use JSON;
use File::Temp qw(tempdir);

use Percona::Test;
use Sandbox;
use Percona::Test::Mock::UserAgent;
use Percona::Test::Mock::AgentLogger;
require "$trunk/bin/pt-agent";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
my $dsn = $sb->dsn_for('master');
my $o   = new OptionParser();
$o->get_specs("$trunk/bin/pt-agent");
$o->get_opts();
my $cxn = Cxn->new(
   dsn_string   => $dsn,
   OptionParser => $o,
   DSNParser    => $dp,
);

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

# Fake --lib and --spool dirs.
my $tmpdir = tempdir("/tmp/pt-agent.$PID.XXXXXX"); #, CLEANUP => 1);
mkdir "$tmpdir/spool" or die "Error making $tmpdir/spool: $OS_ERROR";

my @log;
my $logger = Percona::Test::Mock::AgentLogger->new(log => \@log);
pt_agent::_logger($logger);

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
   uuid     => '123',
   hostname => 'host',
   username => 'user',
   links    => {
      self   => '/agents/123',
      config => '/agents/123/config',
   },
);

my $daemon = Daemon->new(
   daemonzie => 0,
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

my $config = Percona::WebAPI::Resource::Config->new(
   ts      => 1363720060,
   name    => 'Default',
   options => {
      'lib'            => $tmpdir,          # required
      'spool'          => "$tmpdir/spool",  # required
      'check-interval' => "11",
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
   ts             => 100,
   name           => 'query-history',
   run_schedule   => '1 * * * *',
   spool_schedule => '2 * * * *',
   tasks          => [ $run0 ],
   links          => {
      self => '/query-history',
      data => '/query-history/data',
   },
);

my $run1  = Percona::WebAPI::Resource::Task->new(
   name    => 'start-query-history',
   number  => '0',
   program => 'echo "start-qh"',
);

my $start_qh = Percona::WebAPI::Resource::Service->new(
   ts             => '100',
   name           => 'start-query-history',
   meta           => 1,
   tasks          => [ $run1 ],
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
      content => [
         as_hashref($start_qh, with_links => 1),
         as_hashref($svc0, with_links => 1),
      ],
   },
];

my $safeguards = Safeguards->new(
   disk_bytes_free => 1024,
   disk_pct_free   => 1,
);

# The only thing pt-agent must have is the API key in the config file,
# everything else relies on defaults until the first Config is gotten
# from Percona.
my $config_file = pt_agent::get_config_file();
unlink $config_file if -f $config_file;

like(
   $config_file,
   qr/$ENV{LOGNAME}\/\.pt-agent.conf$/,
   "Default config file is ~/.pt-agent.config"
);

pt_agent::write_config(
   config => $config
);

diag(`echo 'api-key=123' >> $config_file`);

is(
   `cat $config_file`,
   "check-interval=11\nlib=$tmpdir\nspool=$tmpdir/spool\napi-key=123\n",
   "Write Config to config file"
); 

pt_agent::save_agent(
   agent   => $agent,
   lib_dir => $tmpdir,
);

my @ok_code = ();  # callbacks
my @oktorun = (
   1,  # 1st main loop check
   0,  # 2nd main loop check
);
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
         # Required args
         agent       => $agent,
         client      => $client,
         daemon      => $daemon,
         interval    => $interval,
         lib_dir     => $tmpdir,
         safeguards  => $safeguards,
         Cxn         => $cxn,
         # Optional args, for testing
         oktorun     => $oktorun,
         json        => $json,
         bin_dir     => "$trunk/bin",
      );
   },
   stderr => 1,
);

is(
   scalar @wait,
   1,
   "Called interval once"
);

is(
   $wait[0],
   11,
   "... used Config->options->check-interval"
);

ok(
   -f "$tmpdir/services/query-history",
   "Created services/query-history"
) or diag($output);

chomp(my $n_files = `ls -1 $tmpdir/services| wc -l | awk '{print \$1}'`);
is(
   $n_files,
   2,
   "... created services/query-history and services/start-query-history"
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
) or diag(Dumper(\@log));

like(
   $crontab,
   qr/pt-agent --send-data query-history$/m,
   "Scheduled --send-data with crontab"
) or diag(Dumper(\@log));
exit;
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

@oktorun = (
   1,  # 1st main loop check
       # First check, error 500
   1,  # 2nd main loop check
       # Init with latest Config and Services
   1,  # 3rd main loop check
       # Same Config and services
   0,  # 4th main loop check
);

# Before the 3rd check, remove the config file (~/.pt-agent.conf) and
# query-history service  file.  When the tool re-GETs these, they'll be
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
         # Required args
         agent       => $agent,
         client      => $client,
         daemon      => $daemon,
         interval    => $interval,
         lib_dir     => $tmpdir,
         Cxn         => $cxn,
         # Optional args, for testing
         oktorun     => $oktorun,
         json        => $json,
      );
   },
   stderr => 1,
);

is_deeply(
   \@wait,
   [ 60, 11, 11 ],
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
diag(`rm -rf $tmpdir/spool/*`);

# When pt-agent manually runs --run-service test-run-at-start, it's going
# to need an API key because it doesn't call its own run_service(), it runs
# another instance of itself with system().  So put the fake API key in
# the default config file.
unlink $config_file if -f $config_file;
diag(`echo "api-key=123" > $config_file`);

$config = Percona::WebAPI::Resource::Config->new(
   ts      => 1363720060,
   name    => 'Test run_once_on_start',
   options => {
      'check-interval' => "15",
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
   ts           => 100,
   name         => 'test-run-at-start',
   run_schedule => '0 0 1 1 *',
   run_once     => 1,  # here's the magic
   tasks        => [ $run0 ],
   links        => {
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

@wait    = ();
@ok_code = ();  # callbacks
@oktorun = (
   1,  # 1st main loop check
       # Run once
   1,  # 2nd main loop check
       # Don't run it again
   0,  # 3d main loop check
);

$output = output(
   sub {
      pt_agent::run_agent(
         # Required args
         agent       => $agent,
         client      => $client,
         daemon      => $daemon,
         interval    => $interval,
         lib_dir     => $tmpdir,
         Cxn         => $cxn,
         # Optional args, for testing
         oktorun     => $oktorun,
         json        => $json,
         bin_dir     => "$trunk/bin/",
      );
   },
   stderr => 1,
);

Percona::Test::wait_for_files("$tmpdir/spool/test-run-at-start/test-run-at-start");

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

chomp($output = `cat $tmpdir/spool/test-run-at-start/test-run-at-start 2>/dev/null`);
ok(
   $output,
   "... service ran at start"
) or diag($output);

chomp($output = `crontab -l`);
unlike(
   $output,
   qr/--run-service test-run-at-start/,
   "... service was not scheduled"
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
