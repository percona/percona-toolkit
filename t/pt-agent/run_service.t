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

$ENV{PTTEST_PRETTY_JSON} = 1;

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

Percona::Toolkit->import(qw(Dumper have_required_args));
Percona::WebAPI::Representation->import(qw(as_hashref));

my @log;
my $logger = Percona::Test::Mock::AgentLogger->new(log => \@log);
pt_agent::_logger($logger);

my $sample = "t/pt-agent/samples";

# Create fake spool and lib dirs.  Service-related subs in pt-agent
# automatically add "/services" to the lib dir, but the spool dir is
# used as-is.
my $tmpdir = tempdir("/tmp/pt-agent.$PID.XXXXXX", CLEANUP => 1);
output(
   sub { pt_agent::init_lib_dir(lib_dir => $tmpdir) }
);
my $spool_dir = "$tmpdir/spool";

sub write_svc_files {
   my (%args) = @_;
   have_required_args(\%args, qw(
      services
   )) or die;
   my $services = $args{services};

   my $output = output(
      sub {
         pt_agent::write_services(
            sorted_services => { added => $services },
            lib_dir         => $tmpdir,
         );
      },
      stderr => 1,
      die    => 1,
   );
}

# #############################################################################
# Create mock client and Agent
# #############################################################################

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
# Simple single task service using a program.
# #############################################################################

my $run0 = Percona::WebAPI::Resource::Task->new(
   name    => 'query-history',
   number  => '0',
   program => "__BIN_DIR__/pt-query-digest --output json $trunk/t/lib/samples/slowlogs/slow008.txt",
   output  => 'spool',
);

my $svc0 = Percona::WebAPI::Resource::Service->new(
   ts             => 100,
   name           => 'query-history',
   run_schedule   => '1 * * * *',
   spool_schedule => '2 * * * *',
   tasks          => [ $run0 ],
);

write_svc_files(
   services => [ $svc0 ],
);

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Agent' },
      content => as_hashref($agent, with_links => 1),
   },
];

my $exit_status;
my $output = output(
   sub {
      $exit_status = pt_agent::run_service(
         api_key     => '123',
         service     => 'query-history',
         lib_dir     => $tmpdir,
         spool_dir   => $spool_dir,
         Cxn         => '',
         # for testing:
         client      => $client,
         agent       => $agent,
         entry_links => $links,
         prefix      => '1',
         json        => $json,
         bin_dir     => "$trunk/bin",
      );
   },
);

ok(
   no_diff(
      "cat $tmpdir/spool/query-history/1.query-history.data",
      "$sample/query-history/data001.json",
      post_pipe => 'grep -v \'"name" :\'',
   ),
   "1 run: spool data (query-history/data001.json)"
) or diag(
   `ls -l $tmpdir/spool/query-history/`,
   `cat $tmpdir/logs/query-history.run`,
   Dumper(\@log)
);

chomp(my $n_files = `ls -1 $spool_dir/query-history/*.data | wc -l | awk '{print \$1}'`);
is(
   $n_files,
   1,
   "1 run: only wrote spool data"
) or diag(`ls -l $spool_dir`);

is(
   $exit_status,
   0,
   "1 run: exit 0"
);

ok(
   -f "$tmpdir/spool/query-history/1.query-history.meta",
   "1 run: .meta file exists"
);

# #############################################################################
# Service with two task, both using a program.
# #############################################################################

diag(`rm -rf $tmpdir/spool/* $tmpdir/services/*`);
@log = ();

# The result is the same as the previous single-run test, but instead of
# having pqd read the slowlog directly, we have the first run cat the
# log to a tmp file which pt-agent should auto-create.  Then pqd in run1
# references this tmp file.

$run0 = Percona::WebAPI::Resource::Task->new(
   name    => 'cat-slow-log',
   number  => '0',
   program => "cat $trunk/t/lib/samples/slowlogs/slow008.txt",
   output  => 'tmp',
);

my $run1 = Percona::WebAPI::Resource::Task->new(
   name    => 'query-history',
   number  => '1',
   program => "__BIN_DIR__/pt-query-digest --output json __RUN_0_OUTPUT__",
   output  => 'spool',
);

$svc0 = Percona::WebAPI::Resource::Service->new(
   ts             => 100,
   name           => 'query-history',
   run_schedule   => '3 * * * *',
   spool_schedule => '4 * * * *',
   tasks          => [ $run0, $run1 ],
);

write_svc_files(
   services => [ $svc0 ],
);

$ua->{responses}->{get} = [
   {
      headers => { 'X-Percona-Resource-Type' => 'Agent' },
      content => as_hashref($agent, with_links => 1),
   },
];

$output = output(
   sub {
      $exit_status = pt_agent::run_service(
         api_key   => '123',
         service   => 'query-history',
         spool_dir => $spool_dir,
         lib_dir   => $tmpdir,
         Cxn       => '',
         # for testing:
         client      => $client,
         agent       => $agent,
         entry_links => $links,
         prefix      => '2',
         json        => $json,
         bin_dir     => "$trunk/bin",
      );
   },
);

ok(
   no_diff(
      "cat $tmpdir/spool/query-history/2.query-history.data",
      "$sample/query-history/data001.json",
      post_pipe => 'grep -v \'"name" :\'',
   ),
   "2 runs: spool data (query-history/data001.json)"
) or diag(
   `ls -l $tmpdir/spool/query-history/`,
   `cat $tmpdir/logs/query-history.run`,
   Dumper(\@log)
);

chomp($n_files = `ls -1 $spool_dir/query-history/*.data | wc -l | awk '{print \$1}'`);
is(
   $n_files,
   1,
   "2 runs: only wrote spool data"
) or diag(`ls -l $spool_dir`);

is(
   $exit_status,
   0,
   "2 runs: exit 0"
);

my @tmp_files = glob "$tmpdir/spool/.tmp/*";
is_deeply(
   \@tmp_files,
   [],
   "2 runs: temp file removed"
);

# #############################################################################
# More realistc: 3 services, multiple tasks, using programs and queries.
# #############################################################################

SKIP: {
   skip 'Cannot connect to sandbox master', 5 unless $dbh;
   skip 'No HOME environment variable', 5 unless $ENV{HOME};

   diag(`rm -rf $tmpdir/spool/* $tmpdir/services/*`);
   @log = ();

   my (undef, $old_genlog) = $dbh->selectrow_array("SHOW VARIABLES LIKE 'general_log_file'");

   my $new_genlog = "$tmpdir/genlog";

   # First service: set up
   my $task00 = Percona::WebAPI::Resource::Task->new(
      name    => 'disable-gen-log',
      number  => '0',
      query   => "SET GLOBAL general_log=OFF",
   );
   my $task01 = Percona::WebAPI::Resource::Task->new(
      name    => 'set-gen-log-file',
      number  => '1',
      query   => "SET GLOBAL general_log_file='$new_genlog'",
   );
   my $task02 = Percona::WebAPI::Resource::Task->new(
      name    => 'enable-gen-log',
      number  => '2',
      query   => "SET GLOBAL general_log=ON",
   );
   my $svc0 = Percona::WebAPI::Resource::Service->new(
      ts             => 100,
      name           => 'enable-gen-log',
      run_schedule   => '1 * * * *',
      spool_schedule => '2 * * * *',
      tasks          => [ $task00, $task01, $task02 ],
   );

   # Second service: the actual service
   my $task10 = Percona::WebAPI::Resource::Task->new(
      name    => 'query-history',
      number  => '1',
      program => "$trunk/bin/pt-query-digest --output json --type genlog $new_genlog",
      output  => 'spool',
   );
   my $svc1 = Percona::WebAPI::Resource::Service->new(
      ts             => 100,
      name           => 'query-history',
      run_schedule   => '3 * * * *',
      spool_schedule => '4 * * * *',
      tasks          => [ $task10 ],
   );

   # Third service: tear down
   my $task20 = Percona::WebAPI::Resource::Task->new(
      name    => 'disable-gen-log',
      number  => '0',
      query   => "SET GLOBAL general_log=OFF",
   );
   my $task21 = Percona::WebAPI::Resource::Task->new(
      name    => 'set-gen-log-file',
      number  => '1',
      query   => "SET GLOBAL general_log_file='$old_genlog'",
   );
   my $task22 = Percona::WebAPI::Resource::Task->new(
      name    => 'enable-gen-log',
      number  => '2',
      query   => "SET GLOBAL general_log=ON",
   );
   my $svc2 = Percona::WebAPI::Resource::Service->new(
      ts             => 100,
      name           => 'disable-gen-log',
      run_schedule   => '5 * * * *',
      spool_schedule => '6 * * * *',
      tasks          => [ $task20, $task21, $task22 ],
   );

   write_svc_files(
      services => [ $svc0, $svc1, $svc2 ],
   );

   $ua->{responses}->{get} = [
      {
         headers => { 'X-Percona-Resource-Type' => 'Agent' },
         content => as_hashref($agent, with_links => 1),
      },
      {
         headers => { 'X-Percona-Resource-Type' => 'Agent' },
         content => as_hashref($agent, with_links => 1),
      },
      {
         headers => { 'X-Percona-Resource-Type' => 'Agent' },
         content => as_hashref($agent, with_links => 1),
      },
   ];

   my $cxn = Cxn->new(
      dsn_string   => $dsn,
      OptionParser => $o,
      DSNParser    => $dp,
   );

   # Run the first service.
   $output = output(
      sub {
         $exit_status = pt_agent::run_service(
            api_key   => '123',
            service   => 'enable-gen-log',
            spool_dir => $spool_dir,
            lib_dir   => $tmpdir,
            Cxn       => $cxn,
            # for testing:
            client      => $client,
            agent       => $agent,
            entry_links => $links,
            prefix      => '3',
            json        => $json,
            bin_dir     => "$trunk/bin",
         );
      },
   );

   my (undef, $genlog) = $dbh->selectrow_array(
      "SHOW VARIABLES LIKE 'general_log_file'");
   is(
      $genlog,
      $new_genlog,
      "Task set MySQL var"
   ) or diag($output);

   # Pretend some time passes...

   # The next service doesn't need MySQL, so it shouldn't connect to it.
   # To check this, the genlog before running and after running should
   # be identical.
   `cp $new_genlog $tmpdir/genlog-before`;

   # Run the second service.
   $output = output(
      sub {
         $exit_status = pt_agent::run_service(
            api_key   => '123',
            service   => 'query-history',
            spool_dir => $spool_dir,
            lib_dir   => $tmpdir,
            Cxn       => $cxn,
            # for testing:
            client      => $client,
            agent       => $agent,
            entry_links => $links,
            prefix      => '4',
            json        => $json,
            bin_dir     => "$trunk/bin",
         );
      },
   );

   `cp $new_genlog $tmpdir/genlog-after`;
   my $diff = `diff $tmpdir/genlog-before $tmpdir/genlog-after`;
   is(
      $diff,
      '',
      "Tasks didn't need MySQL, didn't connect to MySQL"
   ) or diag($output);

   # Pretend more time passes...

   # Run the third service.
   $output = output(
      sub {
         $exit_status = pt_agent::run_service(
            api_key   => '123',
            service   => 'disable-gen-log',
            spool_dir => $spool_dir,
            lib_dir   => $tmpdir,
            Cxn       => $cxn,
            # for testing:
            client      => $client,
            agent       => $agent,
            entry_links => $links,
            prefix      => '5',
            json        => $json,
            bin_dir     => "$trunk/bin",
         );
      },
   );
   
   (undef, $genlog) = $dbh->selectrow_array(
      "SHOW VARIABLES LIKE 'general_log_file'");
   is(
      $genlog,
      $old_genlog,
      "Task restored MySQL var"
   ) or diag($output);

   $dbh->do("SET GLOBAL general_log=ON");
   $dbh->do("SET GLOBAL general_log_file='$old_genlog'");
}

# #############################################################################
# Done.
# #############################################################################
done_testing;
