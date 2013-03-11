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
use Time::HiRes qw(time);
   
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-upgrade";

# This runs immediately if the server is already running, else it starts it.
#diag(`$trunk/sandbox/start-sandbox master 12348 >/dev/null`);

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

my $host1_dsn   = $sb->dsn_for('host1');
my $host2_dsn   = $sb->dsn_for('host2');
my $samples     = "$trunk/t/pt-upgrade/samples";
my $exit_status = 0;
my $output;

my $t0 = time;

$output = output(
   sub {
      $exit_status = pt_upgrade::main($host1_dsn, $host2_dsn,
         "$samples/slow_slow.log", qw(--run-time 3),
         '--progress', 'time,1',
   )},
   stderr => 1,
);

my $t = time - $t0;

ok(
   $t >= 3 && $t <= 6,
   "Ran for roughly --run-time seconds"
) or diag($output, 'Actual run time:', $t);

# Exit status 8 = --run-time expired (an no other errors/problems)
is(
   $exit_status,
   8,
   "Exit status 8"
) or diag($output);

like(
   $output,
   qr/Executing queries.+?remain/,
   "--progress while executing queries"
);

# #############################################################################
# Done.
# #############################################################################
#$sb->wipe_clean($dbh2);
$sb->wipe_clean($dbh1);
#diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
#ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
