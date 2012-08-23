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

# PerconaTest.pm sets this because normal tests shouldn't v-c.
delete $ENV{PERCONA_VERSION_CHECK};

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

# Pingback.pm does this too.
my $dir = File::Spec->tmpdir();
my $check_time_file = File::Spec->catfile($dir,'percona-toolkit-version-check');
unlink $check_time_file if -f $check_time_file;

$sb->create_dbs($master_dbh, ['test']);
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');

$output = `PTVCDEBUG=1 $cmd --source F=$cnf,D=test,t=table_1 --where 1=1 --purge 2>&1`;

like(
   $output,
   qr/(?:VersionCheck|Pingback|Percona suggests)/,
   "Looks like the version-check happened"
) or diag($output);

$rows = $master_dbh->selectall_arrayref("SELECT * FROM test.table_1");
is_deeply(
   $rows,
   [],
   "Tool ran after version-check"
) or diag(Dumper($rows));

ok(
   -f $check_time_file,
   "Created percona-toolkit-version-check file"
);

# ###########################################################################
# v-c file should limit checks to 1 per 24 hours
# ###########################################################################

$output = `PTVCDEBUG=1 $cmd --source F=$cnf,D=test,t=table_1 --where 1=1 --purge 2>&1`;

like(
   $output,
   qr/It is not time to --version-checka again/,
   "Doesn't always check because of time limit"
);

unlink $check_time_file if -f $check_time_file;

# ###########################################################################
# Fake v.percona.com not responding by using a different, non-existent URL.
# ###########################################################################

my $t0 = time;

$output = `PTVCDEBUG=1 PERCONA_VERSION_CHECK_URL='http://x.percona.com' $cmd --source F=$cnf,D=test,t=table_1 --where 1=1 --purge 2>&1`;

my $t = time - $t0;

like(
   $output,
   qr/Error.+?GET http:\/\/x\.percona\.com.+?HTTP status 5\d+/,
   "The Percona server didn't respond"
);

# In actuality it should only wait 2s, but on slow boxes all the other
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
# Disable the v-c.
# ###########################################################################

unlink $check_time_file if -f $check_time_file;

$output = `PTVCDEBUG=1 $cmd --source F=$cnf,D=test,t=table_1 --where 1=1 --purge --no-version-check 2>&1`;

unlike(
   $output,
   qr/(?:VersionCheck|Pingback|Percona suggests)/,
   "Looks like --no-version-check disabled the version-check"
) or diag($output);

ok(
   !-f $check_time_file,
   "percona-toolkit-version-check file not created with --no-version-check"
);

# PERCONA_VERSION_CHECK=0 is handled in Pingback, so it will print a line
# for PTVCDEBUG saying why it didn't run.  So we just check that it doesn't
# create the file which also signifies that it didn't run.
$output = `PTVCDEBUG=1 PERCONA_VERSION_CHECK=0 $cmd --source F=$cnf,D=test,t=table_1 --where 1=1 --purge 2>&1`;

ok(
   !-f $check_time_file,
   "Looks like PERCONA_VERSION_CHECK=0 disabled the version-check"
);

# #############################################################################
# Done.
# #############################################################################
unlink $check_time_file if -f $check_time_file;
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
