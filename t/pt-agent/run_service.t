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
# Simple single run service
# #############################################################################

my $run0 = Percona::WebAPI::Resource::Run->new(
   number  => '0',
   program => "$trunk/bin/pt-query-digest",
   options => "--report-format profile $trunk/t/lib/samples/slowlogs/slow008.txt",
   output  => 'spool',
);

my $svc0 = Percona::WebAPI::Resource::Service->new(
   name           => 'query-monitor',
   run_schedule   => '1 * * * *',
   spool_schedule => '2 * * * *',
   runs           => [ $run0 ],
);

write_svc_files(
   services => [ $svc0 ],
);

my $exit_status;
my $output = output(
   sub {
      $exit_status = pt_agent::run_service(
         service   => 'query-monitor',
         spool_dir => $spool_dir,
         lib_dir   => $tmpdir,
      );
   },
   stderr => 1,
);

ok(
   no_diff(
      "cat $tmpdir/spool/query-monitor",
      "$sample/spool001.txt",
   ),
   "1 run: spool data (spool001.txt)"
);

chomp(my $n_files = `ls -1 $spool_dir | wc -l | awk '{print \$1}'`);
is(
   $n_files,
   1,
   "1 run: only wrote spool data (spool001.txt)"
) or diag(`ls -l $spool_dir`);

is(
   $exit_status,
   0,
   "1 run: exit 0"
);

# #############################################################################
# Service with two runs
# #############################################################################

diag(`rm -rf $tmpdir/spool/* $tmpdir/services/*`);

# The result is the same as the previous single-run test, but instead of
# having pqd read the slowlog directly, we have the first run cat the
# log to a tmp file which pt-agent should auto-create.  Then pqd in run1
# references this tmp file.

$run0 = Percona::WebAPI::Resource::Run->new(
   number  => '0',
   program => "cat",
   options => "$trunk/t/lib/samples/slowlogs/slow008.txt",
   output  => 'tmp',
);

my $run1 = Percona::WebAPI::Resource::Run->new(
   number  => '1',
   program => "$trunk/bin/pt-query-digest",
   options => "--report-format profile __RUN_0_OUTPUT__",
   output  => 'spool',
);

$svc0 = Percona::WebAPI::Resource::Service->new(
   name           => 'query-monitor',
   run_schedule   => '3 * * * *',
   spool_schedule => '4 * * * *',
   runs           => [ $run0, $run1 ],
);

write_svc_files(
   services => [ $svc0 ],
);

$output = output(
   sub {
      $exit_status = pt_agent::run_service(
         service   => 'query-monitor',
         spool_dir => $spool_dir,
         lib_dir   => $tmpdir,
      );
   },
   stderr => 1,
);

ok(
   no_diff(
      "cat $tmpdir/spool/query-monitor",
      "$sample/spool001.txt",
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
# Done.
# #############################################################################
done_testing;
