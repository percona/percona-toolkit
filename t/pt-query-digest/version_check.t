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
require "$trunk/bin/pt-query-digest";

# PerconaTest.pm sets this because normal tests shouldn't v-c.
delete $ENV{PERCONA_VERSION_CHECK};

my $output;
my $cmd  = "$trunk/bin/pt-query-digest --limit 1 $trunk/t/lib/samples/slowlogs/slow001.txt";

# Pingback.pm does this too.
my $dir = File::Spec->tmpdir();
my $check_time_file = File::Spec->catfile($dir,'percona-toolkit-version-check');
unlink $check_time_file if -f $check_time_file;

$output = `PTVCDEBUG=1 $cmd 2>&1`;

like(
   $output,
   qr/(?:VersionCheck|Pingback|Percona suggests)/,
   "Looks like the version-check happened"
) or diag($output);

like(
   $output,
   qr/# Query 1: 0 QPS, 0x concurrency, ID 0x7F7D57ACDD8A346E at byte 0/,
   "Tool ran after version-check"
) or diag(Dumper($output));

ok(
   -f $check_time_file,
   "Created percona-toolkit-version-check file"
);

# ###########################################################################
# v-c file should limit checks to 1 per 24 hours
# ###########################################################################

$output = `PTVCDEBUG=1 $cmd 2>&1`;

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

$output = `PTVCDEBUG=1 PERCONA_VERSION_CHECK_URL='http://x.percona.com' $cmd 2>&1`;

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

$output = `PTVCDEBUG=1 $cmd --no-version-check 2>&1`;

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
$output = `PTVCDEBUG=1 PERCONA_VERSION_CHECK=0 $cmd 2>&1`;

ok(
   !-f $check_time_file,
   "Looks like PERCONA_VERSION_CHECK=0 disabled the version-check"
);

# #############################################################################
# Done.
# #############################################################################
unlink $check_time_file if -f $check_time_file;
done_testing;
exit;
