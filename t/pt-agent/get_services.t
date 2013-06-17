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

my @log;
my $logger = Percona::Test::Mock::AgentLogger->new(log => \@log);
pt_agent::_logger($logger);

# Fake --lib and --spool dirs.
my $tmpdir = tempdir("/tmp/pt-agent.$PID.XXXXXX", CLEANUP => 1);
output( sub {
   pt_agent::init_lib_dir(lib_dir => $tmpdir);
});

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

my @cmds;
my $exec_cmd = sub {
   my $cmd = shift;
   push @cmds, $cmd;
   return 0;
};

# #############################################################################
# Test get_services()
# #############################################################################

# query-history

my $run0 = Percona::WebAPI::Resource::Task->new(
   name    => 'query-history',
   number  => '0',
   program => 'pt-query-digest --output json',
   output  => 'spool',
);

my $qh = Percona::WebAPI::Resource::Service->new(
   ts             => '100',
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
   output  => 'spool',
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
      headers => { 'X-Percona-Resource-Type' => 'Service' },
      content => [
         as_hashref($qh, with_links => 1),
         as_hashref($start_qh, with_links => 1),
      ],
   },
];

my $services = {};
my $success  = 0;

$output = output(
   sub {
      ($services, $success) = pt_agent::get_services(
         # Required args
         link        => '/agents/123/services',
         agent       => $agent,
         client      => $client,
         lib_dir     => $tmpdir,
         services    => $services,
         # Optional args, for testing
         json        => $json,
         bin_dir     => "$trunk/bin/",
         exec_cmd    => $exec_cmd,
      );
   },
   stderr => 1,
);

is(
   $success,
   1,
   "Success"
);

is(
   ref $services,
   'HASH',
   "Return services as hashref"
) or diag(Dumper($services));

is(
   scalar keys %$services,
   2,
   'Only 2 services'
) or diag(Dumper($services));

ok(
   exists $services->{'query-history'},
   "services hashref keyed on service name"
) or diag(Dumper($services));

isa_ok(
   ref $services->{'query-history'},
   'Percona::WebAPI::Resource::Service',
   'services->{query-history}'
);

my $crontab = -f "$tmpdir/crontab" ? slurp_file("$tmpdir/crontab") : '';
is(
   $crontab,
   "1 * * * * $trunk/bin/pt-agent --run-service query-history
2 * * * * $trunk/bin/pt-agent --send-data query-history
",
   "crontab file"
) or diag($output, `ls -l $tmpdir/*`, Dumper(\@log));

is_deeply(
   \@cmds,
   [
      "$trunk/bin/pt-agent --run-service start-query-history >> $tmpdir/logs/start-stop.log 2>&1",
      "crontab $tmpdir/crontab > $tmpdir/crontab.err 2>&1",
   ],
   "Ran start-service and crontab"
) or diag(Dumper(\@cmds), Dumper(\@log));

ok(
   -f "$tmpdir/services/query-history",
   "Wrote --lib/services/query-history"
);

# #############################################################################
# A more realistic transaction
# #############################################################################

# services/query-history should exist from the previous tests.  For these
# tests, get_services() should update the file, so we empty it and check
# that it's re-created, i.e. updated.
diag(`echo -n > $tmpdir/services/query-history`);
is(
   -s "$tmpdir/services/query-history",
   0,
   "Start: empty --lib/services/query-history"
);

# start-query-history

my $task1 = Percona::WebAPI::Resource::Task->new(
   name    => 'disable-slow-query-log',
   number  => '0',
   query   => "SET GLOBAL slow_query_log=0",
);

my $task2 = Percona::WebAPI::Resource::Task->new(
   name    => 'set-slow-query-log-file',
   number  => '1',
   query   => "SET GLOBAL slow_query_log_file='/tmp/slow.log'",
);

my $task3 = Percona::WebAPI::Resource::Task->new(
   name    => 'set-long-query-time',
   number  => '2',
   query   => "SET GLOBAL long_query_time=0.01",
);

my $task4 = Percona::WebAPI::Resource::Task->new(
   name    => 'enable-slow-query-log',
   number  => '3',
   query   => "SET GLOBAL slow_query_log=1",
);

$start_qh = Percona::WebAPI::Resource::Service->new(
   ts             => '100',
   name           => 'start-query-history',
   tasks          => [ $task1, $task2, $task3, $task4 ],
   meta           => 1,
   links          => {
      self => '/query-history',
      data => '/query-history/data',
   },
);

# stop-query-history

my $task5 = Percona::WebAPI::Resource::Task->new(
   name    => 'disable-slow-query-log',
   number  => '0',
   query   => "SET GLOBAL slow_query_log=0",
);

my $stop_qh = Percona::WebAPI::Resource::Service->new(
   ts             => '100',
   name           => 'stop-query-history',
   tasks          => [ $task5 ],
   meta           => 1,
   links          => {
      self => '/query-history',
      data => '/query-history/data',
   },
);

# We'll use query-history from the previous tests.

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Service' },
      content => [
         as_hashref($start_qh, with_links => 1),
         as_hashref($stop_qh,  with_links => 1),
         as_hashref($qh,       with_links => 1),  # from previous tests
      ],
   },
];

@log      = ();
@cmds     = ();
$services = {};
$success  = 0;

$output = output(
   sub {
      ($services, $success) = pt_agent::get_services(
         # Required args
         link        => '/agents/123/services',
         agent       => $agent,
         client      => $client,
         lib_dir     => $tmpdir,
         services    => $services,
         # Optional args, for testing
         json        => $json,
         bin_dir     => "$trunk/bin/",
         exec_cmd    => $exec_cmd,
      );
   },
   stderr => 1,
);

is_deeply(
   \@cmds,
   [
      "$trunk/bin/pt-agent --run-service start-query-history >> $tmpdir/logs/start-stop.log 2>&1",
      "crontab $tmpdir/crontab > $tmpdir/crontab.err 2>&1",
   ],
   "Start: ran start-query-history"
) or diag(Dumper(\@cmds), $output);

ok(
   -f "$tmpdir/services/start-query-history",
   "Start: added --lib/services/start-query-history"
) or diag($output);

ok(
   -f "$tmpdir/services/stop-query-history",
   "Start: added --lib/services/stop-query-history"
) or diag($output);

my $contents = slurp_file("$tmpdir/services/query-history");
like(
   $contents,
   qr/query-history/,
   "Start: updated --lib/services/query-history"
) or diag($output);

$crontab = slurp_file("$tmpdir/crontab");
is(
   $crontab,
   "1 * * * * $trunk/bin/pt-agent --run-service query-history
2 * * * * $trunk/bin/pt-agent --send-data query-history
",
   "Start: only scheduled query-history"
) or diag($output);

# #############################################################################
# Update and restart a service
# #############################################################################

# pt-agent should remove a service's --lib/meta/ files when restarting,
# so create one and check that it's removed.
diag(`touch $tmpdir/meta/query-history.foo`);
ok(
   -f "$tmpdir/meta/query-history.foo",
   "Restart: meta file exists"
);

$qh = Percona::WebAPI::Resource::Service->new(
   ts             => '200',  # was 100
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
      headers => { 'X-Percona-Resource-Type' => 'Service' },
      content => [
         as_hashref($start_qh, with_links => 1),  # has not changed
         as_hashref($stop_qh,  with_links => 1),  # has not changed
         as_hashref($qh,       with_links => 1),
      ],
   },
];

@log      = ();
@cmds     = ();
$success  = 0;

$output = output(
   sub {
      ($services, $success) = pt_agent::get_services(
         # Required args
         link        => '/agents/123/services',
         agent       => $agent,
         client      => $client,
         lib_dir     => $tmpdir,
         services    => $services,  # retval from previous call
         # Optional args, for testing
         json        => $json,
         bin_dir     => "$trunk/bin/",
         exec_cmd    => $exec_cmd,
      );
   },
   stderr => 1,
);

is_deeply(
   \@cmds,
   [
      "$trunk/bin/pt-agent --run-service stop-query-history >> $tmpdir/logs/start-stop.log 2>&1",
      "$trunk/bin/pt-agent --run-service start-query-history >> $tmpdir/logs/start-stop.log 2>&1",
      "crontab $tmpdir/crontab > $tmpdir/crontab.err 2>&1",
   ],
   "Restart: ran stop-query-history then start-query-history"
) or diag(Dumper(\@cmds), $output);

ok(
   !-f "$tmpdir/meta/query-history.foo",
   "Restart: meta file removed"
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
done_testing;
