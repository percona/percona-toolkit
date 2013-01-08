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
require "$trunk/bin/pt-agent";

Percona::Toolkit->import(qw(have_required_args Dumper));

my $sample = "t/pt-agent/samples";

sub test_make_new_crontab {
   my (%args) = @_;
   have_required_args(\%args, qw(
      file
      name
      services
   )) or die;
   my $file     = $args{file};
   my $name     = $args{name};
   my $services = $args{services};

   my $crontab_list   = slurp_file("$trunk/$sample/$file.in");

   my $new_crontab = pt_agent::make_new_crontab(
      services     => $services,
      crontab_list => $crontab_list,
   );

   ok(
      no_diff(
         $new_crontab,
         "$sample/$file.out",
         cmd_output => 1,
      ),
      "$name"
   );
} 

# #############################################################################
# Empty crontab, new service.
# #############################################################################

my $run0 = Percona::WebAPI::Resource::Run->new(
   number  => '0',
   program => 'pt-query-digest',
   options => '--output json',
   output  => 'spool',
);

my $svc0 = Percona::WebAPI::Resource::Service->new(
   name     => 'query-monitor',
   alias    => 'Query Monitor',
   schedule => '* 8 * * 1,2,3,4,5',
   runs     => [ $run0 ],
);

test_make_new_crontab(
   name => "crontab001",
   file => "crontab001",
   services => [ $svc0 ],
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
