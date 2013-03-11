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
use File::Basename;
use File::Temp qw(tempdir);

$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-upgrade";

# This runs immediately if the server is already running, else it starts it.
diag(`$trunk/sandbox/start-sandbox master 12348 >/dev/null`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('host1');
my $dbh2 = $sb->get_dbh_for('host2');

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox host1'; 
}
elsif ( !$dbh2 ) {
   plan skip_all => 'Cannot connect to sandbox host2';
}

my $host1_dsn = $sb->dsn_for('host1');
my $host2_dsn = $sb->dsn_for('host2');

my $tmpdir = tempdir("/tmp/pt-upgrade.$PID.XXXXXX", CLEANUP => 1);

my $sample      = "t/pt-upgrade/samples";
my $samples_dir = "$trunk/t/pt-upgrade/samples";

opendir(my $dh, $samples_dir) or die "Cannot open $samples_dir: $OS_ERROR";

sub load_sample_sql_files {
   my ($sampleno) = @_;

   if ( -f "$samples_dir/$sampleno/tables.sql" ) {
      $sb->load_file('host1', "$sample/$sampleno/tables.sql", undef, no_wait => 1);
      $sb->load_file('host2', "$sample/$sampleno/tables.sql", undef, no_wait => 1);
   }
   if ( -f "$samples_dir/$sampleno/host1.sql" ) {
      $sb->load_file('host1', "$sample/$sampleno/host1.sql", undef, no_wait => 1);
   }
   if ( -f "$samples_dir/$sampleno/host2.sql" ) {
      $sb->load_file('host2', "$sample/$sampleno/host2.sql", undef, no_wait => 1);
   }
}

while ( my $sampleno = readdir $dh ) {
   next unless $sampleno =~ m/^\d+$/;

   my $conf = "$samples_dir/$sampleno/conf";

   load_sample_sql_files($sampleno);

   foreach my $log ( glob("$samples_dir/$sampleno/*.log") ) {
      (my $basename = basename($log)) =~ s/\.\S+$//;

      my $sed;
      if ( -f "$samples_dir/$sampleno/$basename.sed" ) {
         chomp($sed = `cat $samples_dir/$sampleno/$basename.sed`);
      }

      diag(`rm -rf $tmpdir/*`);        

      # First, run the log on host1 and save the results. 
      my $save_results_output = output(
         sub { pt_upgrade::main(
            (-f $conf ? ('--config', $conf) : ()),
            $log,
            $host1_dsn,
            '--save-results', $tmpdir
         ) },
         stderr => 1,
      );

      # Second, compare the results to host2.
      my $output = output(
         sub { pt_upgrade::main(
            (-f $conf ? ('--config', $conf) : ()),
            $tmpdir,
            $host2_dsn,
         ) },
         stderr => 1,
      );

      if ( -f "$samples_dir/$sampleno/${basename}_results.txt" ) {
         ok(
            no_diff(
               $output,
               "$sample/$sampleno/${basename}_results.txt",
               cmd_output => 1,
               sed => [
                  q{'s/Results directory: .*/Results directory: .../'},
                  q{'s/Reading results from .*/Reading results from .../'},
                  q{'s/Saving results in .*/Saving results in .../'},
                  q{'s/  hostname:  .*/  hostname:  .../'},
                  q{'s/  MySQL:     .*/  MySQL:     .../'},
                  ($sed ? $sed : ()),
               ],
            ),
            "$sampleno: $basename.txt"
         ) or diag("\n\n---- DIFF ----\n\n", $test_diff,
                   "\n\n---- SAVE RESULTS ----\n\n", $save_results_output,
                   `cat $tmpdir/*`, "\n",
                   "\n\n---- OUTPUT ----\n\n",  $output);
      }
   }
}

close $dh;

# #############################################################################
# Done.
# #############################################################################
#$sb->wipe_clean($dbh2);
$sb->wipe_clean($dbh1);
diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
