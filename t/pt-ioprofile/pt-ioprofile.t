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

use PerconaTest;
use DSNParser;
use Sandbox;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => "Cannot connect to master sandbox";
}
else {
   plan tests => 4;
}

my $output = "";

$output = `$trunk/bin/pt-ioprofile --help 2>&1`;
like(
   $output,
   qr/--version/,
   "--help"
);


my $t0 = time;
$output = `$trunk/bin/pt-ioprofile --run-time 3 2>&1`;
my $t1 = time;

like(
   $output,
   qr/Tracing process ID \d+/,
   "Runs without a file (bug 925778)"
);

# If the system is really slow, it may take a second to process the files
# and then clean up all the temp stuff.  In any case, the default run-time
# is 30s so it should be way less than that.
cmp_ok(
   $t1 - $t0,
   '<',
   5,
   "Runs for --run-time"
);

# #############################################################################
# Short options.
# #############################################################################
$output = `$trunk/bin/pt-ioprofile --run-time 2 --b theprocname 2>&1`;
like(
   $output,
   qr/Cannot determine PID of theprocname process/,
   "Short option -b (--profile-process)"
);

# #############################################################################
# Done.
# #############################################################################
exit;
