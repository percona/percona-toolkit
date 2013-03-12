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

my $host1_dsn   = $sb->dsn_for('host1');
my $host2_dsn   = $sb->dsn_for('host2');
my $tmpdir      = tempdir("/tmp/pt-upgrade.$PID.XXXXXX", CLEANUP => 1);
my $samples     = "$trunk/t/pt-upgrade/samples";
my $exit_status = 0;
my $output;

# #############################################################################
# Executing queries
# #############################################################################

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
   "Exec queries: ran for roughly --run-time seconds"
) or diag($output, 'Actual run time:', $t);

# Exit status 8 = --run-time expired (an no other errors/problems)
is(
   $exit_status,
   8,
   "Exec queries: exit status 8"
) or diag($output);

like(
   $output,
   qr/slow_slow.log.+?remain/,
   "Exec queries: --progress"
);

# #############################################################################
# Saving results
# #############################################################################

$t0 = time;

$output = output(
   sub {
      $exit_status = pt_upgrade::main($host1_dsn,
         '--save-results', $tmpdir,
         "$samples/slow_slow.log", qw(--run-time 3),
         '--progress', 'time,1',
   )},
   stderr => 1,
);

$t = time - $t0;

ok(
   $t >= 3 && $t <= 6,
   "Save results: ran for roughly --run-time seconds"
) or diag($output, 'Actual run time:', $t);

# Exit status 8 = --run-time expired (an no other errors/problems)
is(
   $exit_status,
   8,
   "Save results: exit status 8"
) or diag($output);

like(
   $output,
   qr/slow_slow.log.+?remain/,
   "Save results: --progress"
);

# #############################################################################
# Done.
# #############################################################################
#$sb->wipe_clean($dbh2);
$sb->wipe_clean($dbh1);
diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
