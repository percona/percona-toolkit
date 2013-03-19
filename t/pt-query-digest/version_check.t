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
use Data::Dumper;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-query-digest";

my $output;
my $cmd = "$trunk/bin/pt-query-digest --limit 1 $trunk/t/lib/samples/slowlogs/slow001.txt";

my $vc_file = VersionCheck::version_check_file();
unlink $vc_file if -f $vc_file;

# Normally --version-check is on by default, but in dev/testing envs,
# there's going to be a .bzr dir that auto-disables --version-check so
# our dev/test boxes don't flood the v-c database.  Consequently,
# have have to explicitly give --version-check to force the check.

$output = `PTDEBUG=1 $cmd --version-check 2>&1`;

like(
   $output,
   qr/VersionCheck:\d+ \d+ Server response/,
   "Looks like the version-check happened"
) or diag($output);

ok(
   -f $vc_file,
   "Version check file was created"
) or diag($output);

like(
   $output,
   qr/# Query 1: 0 QPS, 0x concurrency, ID 0x7F7D57ACDD8A346E at byte 0/,
   "Tool ran after version-check"
) or diag(Dumper($output));

# ###########################################################################
# v-c file should limit checks to 1 per 24 hours
# ###########################################################################

my $orig_vc_file = `cat $vc_file 2>/dev/null`;

$output = `PTDEBUG=1 $cmd --version-check 2>&1`;

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

$output = `PTDEBUG=1 PERCONA_VERSION_CHECK_URL='http://x.percona.com' $cmd --version-check 2>&1`;

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

$output = `PTDEBUG=1 $cmd --no-version-check 2>&1`;

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

$output = `PTDEBUG=1 $cmd 2>&1`;

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

diag(`cp $trunk/bin/pt-query-digest /tmp/pt-query-digest.$PID`);

# Notice: --version-check is NOT on the command line, because
# it should be enabled by default.
$output = `PTDEBUG=1 /tmp/pt-query-digest.$PID --limit 1 $trunk/t/lib/samples/slowlogs/slow001.txt 2>&1`;

like(
   $output,
   qr/VersionCheck:\d+ \d+ Server response/,
   "Looks like the version-check happened by default"
) or diag($output);

ok(
   -f $vc_file,
   "Version check file was created by default"
) or diag($output);

unlink "/tmp/pt-query-digest.$PID" if "/tmp/pt-query-digest.$PID";

# #############################################################################
# Done.
# #############################################################################
unlink $vc_file if -f $vc_file;
done_testing;
