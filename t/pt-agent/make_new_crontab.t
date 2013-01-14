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
use File::Temp qw(tempfile);

use Percona::Test;
require "$trunk/bin/pt-agent";

Percona::Toolkit->import(qw(have_required_args Dumper));

my $sample = "t/pt-agent/samples";

sub test_make_new_crontab {
   my (%args) = @_;
   have_required_args(\%args, qw(
      file
      services
   )) or die;
   my $file     = $args{file};
   my $services = $args{services};

   my $crontab_list = slurp_file("$trunk/$sample/$file.in");

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
      $args{name} || $file,
   );
} 

my $run0 = Percona::WebAPI::Resource::Run->new(
   number  => '0',
   program => 'pt-query-digest',
   options => '--output json',
   output  => 'spool',
);

my $svc0 = Percona::WebAPI::Resource::Service->new(
   name           => 'query-monitor',
   run_schedule   => '* 8 * * 1,2,3,4,5',
   spool_schedule => '* 9 * * 1,2,3,4,5',
   runs           => [ $run0 ],
);

# Empty crontab, add the service.
test_make_new_crontab(
   file => "crontab001",
   services => [ $svc0 ],
);

# Crontab has another line, add the service to it.
test_make_new_crontab(
   file => "crontab002",
   services => [ $svc0 ],
);

# Crontab has another line and an old service, remove the old service
# and add the current service.
test_make_new_crontab(
   file => "crontab003",
   services => [ $svc0 ],
);

# #############################################################################
# Use real crontab.
# #############################################################################

# The previous tests pass in a crontab file to make testing easier.
# Now test that make_new_crontab() will run `crontab -l' if not given
# input.  To test this, we add a fake line to our crontab.  If
# make_new_crontab() really runs `crontab -l', then this fake line
# will be in the new crontab it returns.

my $crontab = `crontab -l 2>/dev/null`;
SKIP: {
   skip 'Crontab is not empty', 3 if $crontab;

   my ($fh, $file) = tempfile();
   print {$fh} "* 0  *  *  *  date > /dev/null";
   close $fh or warn "Cannot close $file: $OS_ERROR";
   my $output = `crontab $file 2>&1`;

   $crontab = `crontab -l 2>&1`;

   is(
      $crontab,
      "* 0  *  *  *  date > /dev/null",
      "Set other crontab line"
   ) or diag($output);

   unlink $file or warn "Cannot remove $file: $OS_ERROR";

   my $new_crontab = pt_agent::make_new_crontab(
      services => [ $svc0 ],
   );

   is(
      $new_crontab,
      "* 0  *  *  *  date > /dev/null
* 8 * * 1,2,3,4,5 pt-agent --run-service query-monitor
* 9 * * 1,2,3,4,5 pt-agent --send-data query-monitor
",
      "Runs crontab -l by default"
   );

   system("crontab -r 2>/dev/null");
   $crontab = `crontab -l 2>/dev/null`;
   is(
      $crontab,
      "",
      "Removed crontab"
   );
};

# #############################################################################
# Done.
# #############################################################################
done_testing;
