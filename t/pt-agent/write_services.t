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

my $json   = JSON->new->canonical([1])->pretty;
my $sample = "t/pt-agent/samples";
my $tmpdir = tempdir("/tmp/pt-agent.$PID.XXXXXX", CLEANUP => 1);

mkdir "$tmpdir/services" or die "Error mkdir $tmpdir/services: $OS_ERROR";

my @log;
my $logger = Percona::Test::Mock::AgentLogger->new(log => \@log);
pt_agent::_logger($logger);

sub test_write_services {
   my (%args) = @_;
   have_required_args(\%args, qw(
      services
      file
   )) or die;
   my $services = $args{services};
   my $file     = $args{file};

   die "$trunk/$sample/$file does not exist"
      unless -f "$trunk/$sample/$file";

   my $output = output(
      sub {
         pt_agent::write_services(
            sorted_services => $services,
            lib_dir         => $tmpdir,
            json            => $json,
         );
      },
      stderr => 1,
   );

   foreach my $service ( @{$services->{added}} ) {
      my $name = $service->name;
      ok(
         no_diff(
            "cat $tmpdir/services/$name 2>/dev/null",
            "$sample/$file",
         ),
         "$file $name"
      ) or diag($output, `cat $tmpdir/services/$name`);
   }

   diag(`rm -rf $tmpdir/*`);
}

my $run0 = Percona::WebAPI::Resource::Task->new(
   name    => 'query-history',
   number  => '0',
   program => "pt-query-digest",
   options => "--report-format profile slow008.txt",
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

# Key thing here is that the links are written because
# --send-data <service> requires them.

my $sorted_services = {
   added   => [ $svc0 ],
   updated => [],
   removed => [],
};

test_write_services(
   services => $sorted_services,
   file     => "write_services001",
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
