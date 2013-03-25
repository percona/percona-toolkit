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

my $sample = "t/pt-agent/samples";

# Create fake spool and lib dirs.  Service-related subs in pt-agent
# automatically add "/services" to the lib dir, but the spool dir is
# used as-is.
my $tmpdir = tempdir("/tmp/pt-agent.$PID.XXXXXX", CLEANUP => 1);
mkdir "$tmpdir/spool"    or die "Error making $tmpdir/spool: $OS_ERROR";
mkdir "$tmpdir/services" or die "Error making $tmpdir/services: $OS_ERROR";
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
            services => $services,
            lib_dir  => $tmpdir,
         );
      },
      stderr => 1,
      die    => 1,
   );
}

# #############################################################################
# Simple single task service using a program.
# #############################################################################

my $run0 = Percona::WebAPI::Resource::Task->new(
   name    => 'query-history',
   number  => '0',
   program => "$trunk/bin/pt-query-digest",
   options => "--output json $trunk/t/lib/samples/slowlogs/slow008.txt",
   output  => 'spool',
);

my $svc0 = Percona::WebAPI::Resource::Service->new(
   name           => 'query-history',
   run_schedule   => '1 * * * *',
   spool_schedule => '2 * * * *',
   tasks          => [ $run0 ],
);

write_svc_files(
   services => [ $svc0 ],
);

my $exit_status;
my $output = output(
   sub {
      $exit_status = pt_agent::run_service(
         service   => 'query-history',
         spool_dir => $spool_dir,
         lib_dir   => $tmpdir,
         Cxn       => '',
      );
   },
   stderr => 1,
);

ok(
   no_diff(
      "cat $tmpdir/spool/query-history",
      "$sample/query-history/data001.json",
   ),
   "1 run: spool data (query-history/data001.json)"
);

chomp(my $n_files = `ls -1 $spool_dir | wc -l | awk '{print \$1}'`);
is(
   $n_files,
   1,
   "1 run: only wrote spool data (query-history/data001.json)"
) or diag(`ls -l $spool_dir`);

is(
   $exit_status,
   0,
   "1 run: exit 0"
);

# #############################################################################
# Service with two task, both using a program.
# #############################################################################

diag(`rm -rf $tmpdir/spool/* $tmpdir/services/*`);

# The result is the same as the previous single-run test, but instead of
# having pqd read the slowlog directly, we have the first run cat the
# log to a tmp file which pt-agent should auto-create.  Then pqd in run1
# references this tmp file.

$run0 = Percona::WebAPI::Resource::Task->new(
   name    => 'cat-slow-log',
   number  => '0',
   program => "cat",
   options => "$trunk/t/lib/samples/slowlogs/slow008.txt",
   output  => 'tmp',
);

my $run1 = Percona::WebAPI::Resource::Task->new(
   name    => 'query-history',
   number  => '1',
   program => "$trunk/bin/pt-query-digest",
   options => "--output json __RUN_0_OUTPUT__",
   output  => 'spool',
);

$svc0 = Percona::WebAPI::Resource::Service->new(
   name           => 'query-history',
   run_schedule   => '3 * * * *',
   spool_schedule => '4 * * * *',
   tasks          => [ $run0, $run1 ],
);

write_svc_files(
   services => [ $svc0 ],
);

$output = output(
   sub {
      $exit_status = pt_agent::run_service(
         service   => 'query-history',
         spool_dir => $spool_dir,
         lib_dir   => $tmpdir,
         Cxn       => '',
      );
   },
   stderr => 1,
);

ok(
   no_diff(
      "cat $tmpdir/spool/query-history",
      "$sample/query-history/data001.json",
   ),
   "2 runs: spool data"
);

chomp($n_files = `ls -1 $spool_dir | wc -l | awk '{print \$1}'`);
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

# Get the temp file created by pt-agent by matching it from
# the output line like:
#   2013-01-08T13:14:23.627040 INFO Run 0: cat /Users/daniel/p/pt-agent/t/lib/samples/slowlogs/slow008.txt > /var/folders/To/ToaPSttnFbqvgRqcHPY7qk+++TI/-Tmp-/q1EnzzlDoL
my ($tmpfile) = $output =~ m/cat \S+ > (\S+)/;

ok(
   ! -f $tmpfile,
   "2 runs: temp file removed"
);

# #############################################################################
# More realistc: 3 services, multiple tasks, using programs and queries.
# #############################################################################

SKIP: {
   skip 'Cannot connect to sandbox master', 5 unless $dbh;
   skip 'No HOME environment variable', 5 unless $ENV{HOME};

   diag(`rm -rf $tmpdir/spool/* $tmpdir/services/*`);

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
      name           => 'enable-gen-log',
      run_schedule   => '1 * * * *',
      spool_schedule => '2 * * * *',
      tasks          => [ $task00, $task01, $task02 ],
   );

   # Second service: the actual service
   my $task10 = Percona::WebAPI::Resource::Task->new(
      name    => 'query-history',
      number  => '1',
      program => "$trunk/bin/pt-query-digest",
      options => "--output json --type genlog $new_genlog",
      output  => 'spool',
   );
   my $svc1 = Percona::WebAPI::Resource::Service->new(
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
      name           => 'disable-gen-log',
      run_schedule   => '5 * * * *',
      spool_schedule => '6 * * * *',
      tasks          => [ $task20, $task21, $task22 ],
   );

   write_svc_files(
      services => [ $svc0, $svc1, $svc2 ],
   );

   my $cxn = Cxn->new(
      dsn_string   => $dsn,
      OptionParser => $o,
      DSNParser    => $dp,
   );

   # Run the first service.
   $output = output(
      sub {
         $exit_status = pt_agent::run_service(
            service   => 'enable-gen-log',
            spool_dir => $spool_dir,
            lib_dir   => $tmpdir,
            Cxn       => $cxn,
         );
      },
      stderr => 1,
   );

   my (undef, $genlog) = $dbh->selectrow_array("SHOW VARIABLES LIKE 'general_log_file'");
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
            service   => 'query-history',
            spool_dir => $spool_dir,
            lib_dir   => $tmpdir,
            Cxn       => $cxn,
         );
      },
      stderr => 1,
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
            service   => 'disable-gen-log',
            spool_dir => $spool_dir,
            lib_dir   => $tmpdir,
            Cxn       => $cxn,
         );
      },
      stderr => 1,
   );
   
   (undef, $genlog) = $dbh->selectrow_array("SHOW VARIABLES LIKE 'general_log_file'");
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
