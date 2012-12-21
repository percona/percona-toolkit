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
my $have_strace = `which strace 2>/dev/null`;

if ( !$dbh ) {
   plan skip_all => "Cannot connect to master sandbox";
}
elsif ( !$have_strace ) {
   plan skip_all => 'strace is not installed or not in PATH';
}

my $output = `$trunk/bin/pt-ioprofile --help 2>&1`;
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
# and then clean up all the temp stuff. We'll give it a few seconds benefit
# of the doubt.
cmp_ok(
   int($t1 - $t0),
   '<=',
   6,
   "Runs for --run-time, more or less"
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
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
