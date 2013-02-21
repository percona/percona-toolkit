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

use PerconaTest;
use Sandbox;
use Data::Dumper;
use File::Spec;
use Time::HiRes qw(time);
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $rows;
my $output;
my $cnf  = "/tmp/12345/my.sandbox.cnf";
my $cmd  = "$trunk/bin/pt-archiver";
my @args = qw(--dry-run --where 1=1);

my $vc_file = VersionCheck::version_check_file();
unlink $vc_file if -f $vc_file;

$sb->create_dbs($master_dbh, ['test']);
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');

# Normally --version-check is on by default, but in dev/testing envs,
# there's going to be a .bzr dir that auto-disables --version-check so
# our dev/test boxes don't flood the v-c database.  Consequently,
# have have to explicitly give --version-check to force the check.

$output = `PTDEBUG=1 $cmd --source F=$cnf,D=test,t=table_1 --where 1=1 --purge --version-check 2>&1`;

like(
   $output,
   qr/VersionCheck:\d+ \d+ Server response/,
   "Looks like the version-check happened"
) or diag($output);

ok(
   -f $vc_file,
   "Version check file was created"
) or diag($output);

$rows = $master_dbh->selectall_arrayref("SELECT * FROM test.table_1");
is_deeply(
   $rows,
   [],
   "Tool ran after version-check"
) or diag(Dumper($rows), $output);

# ###########################################################################
# v-c file should limit checks to 1 per 24 hours
# ###########################################################################

my $orig_vc_file = `cat $vc_file 2>/dev/null`;

$output = `PTDEBUG=1 $cmd --source F=$cnf,D=test,t=table_1 --where 1=1 --purge --version-check 2>&1`;

like(
   $output,
   qr/0 instances to check/,
   "No instances to check because of time limit"
);

my $new_vc_file = `cat $vc_file 2>/dev/null`;

is(
   $new_vc_file,
   $orig_vc_file,
   "Version check file not changed"
) or diag($output);

unlink $vc_file if -f $vc_file;

# ###########################################################################
# Fake v.percona.com not responding by using a different, non-existent URL.
# ###########################################################################

my $t0 = time;

$output = `PTDEBUG=1 PERCONA_VERSION_CHECK_URL='http://x.percona.com' $cmd --source F=$cnf,D=test,t=table_1 --where 1=1 --purge --version-check 2>&1`;

my $t = time - $t0;

like(
   $output,
   qr/Version check failed: GET on \S+x.percona.com returned HTTP status 5../,
   "The Percona server didn't respond"
);

# In actuality it should only wait 3s, but on slow boxes all the other
# stuff the tool does may cause the time to be much greater than 2.
# If nothing else, this tests that the timeout isn't something crazy
# like 30s.
cmp_ok(
   $t,
   '<',
   6,
   "Tool waited a short while for the Percona server to respond"
);

# ###########################################################################
# Disable --version-check.
# ###########################################################################

unlink $vc_file if -f $vc_file;

$output = `PTDEBUG=1 $cmd --source F=$cnf,D=test,t=table_1 --where 1=1 --purge --no-version-check 2>&1`;

unlike(
   $output,
   qr/VersionCheck/,
   "Looks like --no-version-check disabled the check"
) or diag($output);

ok(
   !-f $vc_file,
   "... version check file was not created"
) or diag(`cat $vc_file`);

# Since this is a test, VersionCheck should detect the .bzr dir
# and disble itself even without --no-version-check.

$output = `PTDEBUG=1 $cmd --source F=$cnf,D=test,t=table_1 --where 1=1 --purge 2>&1`;

like(
   $output,
   qr/\.bzr disables --version-check/,
   "Looks like .bzr disabled the check"
) or diag($output);

unlike(
   $output,
   qr/Updating last check time/,
   "... version check file was not updated"
) or diag($output);

ok(
   !-f $vc_file,
   "... version check file was not created"
) or diag($output, `cat $vc_file`);


# #############################################################################
# Test --version-check as if tool isn't in a dev/test env by copying
# to another dir so VersionCheck won't see a ../.bzr/.
# #############################################################################

unlink $vc_file if -f $vc_file;

diag(`cp $trunk/bin/pt-archiver /tmp/pt-archiver.$PID`);

# Notice: --version-check is NOT on the command line, because
# it should be enabled by default.
$output = `PTDEBUG=1 /tmp/pt-archiver.$PID --source F=$cnf,D=test,t=table_1 --where 1=1 --purge 2>&1`;

like(
   $output,
   qr/VersionCheck:\d+ \d+ Server response/,
   "Looks like the version-check happened by default"
) or diag($output);

ok(
   -f $vc_file,
   "Version check file was created by default"
) or diag($output);

unlink "/tmp/pt-archiver.$PID" if "/tmp/pt-archiver.$PID";

# #############################################################################
# Done.
# #############################################################################
unlink $vc_file if -f $vc_file;
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
