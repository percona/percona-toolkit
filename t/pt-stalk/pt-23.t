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

my $pid_file = "/tmp/pt-stalk.pid.$PID";
my $log_file = "/tmp/pt-stalk.log.$PID";
my $dest     = "/tmp/pt-stalk.collect.$PID";

sub cleanup {
   diag(`rm $pid_file $log_file 2>/dev/null`);
   diag(`rm -rf $dest 2>/dev/null`);
}

cleanup();

# ############################################################################
# Test use option --system-only to prevent password prompt.
# This still makes sense, because if someone uses --password on command line
# together with --system-only, it will still be visible in the ps output
# and we should still warn about it.
# ############################################################################

# Test 1: Check that warning is printed when --password is specified
my $output = `$trunk/bin/pt-stalk --password=secret123 --system-only --no-stalk --iterations=1 --run-time=1 --log=$log_file --pid=$pid_file --dest=$dest 2>&1`;

like(
   $output,
   qr/Providing MySQL password on the command line interface is insecure/m,
   "Warning is printed when --password option is used"
);

cleanup();

# Test 2: Check that warning is printed with short form -p
$output = `$trunk/bin/pt-stalk -p secret123 --system-only --no-stalk --iterations=1 --run-time=1 --log=$log_file --pid=$pid_file --dest=$dest 2>&1`;

like(
   $output,
   qr/Providing MySQL password on the command line interface is insecure/m,
   "Warning is printed when -p option is used"
);

cleanup();

# Test 3: Check that warning is NOT printed when --system-only is used (no password prompts)
$output = `$trunk/bin/pt-stalk --system-only --no-stalk --iterations=1 --run-time=1 --log=$log_file --pid=$pid_file --dest=$dest 2>&1`;

unlike(
   $output,
   qr/Providing MySQL password on the command line interface is insecure/m,
   "Warning is NOT printed when --system-only option is used"
);

cleanup();

# Test 4: Check that warning is printed when --password is specified after --
$output = `$trunk/bin/pt-stalk --system-only --no-stalk --iterations=1 --run-time=1 --log=$log_file --pid=$pid_file --dest=$dest -- --password=secret123 2>&1`;

like(
   $output,
   qr/Providing MySQL password on the command line interface is insecure/m,
   "Warning is printed when --password option is used after --"
);

cleanup();

# Test 5: Check that warning is printed with short form -p after --
$output = `$trunk/bin/pt-stalk --system-only --no-stalk --iterations=1 --run-time=1 --log=$log_file --pid=$pid_file --dest=$dest -- -psecret123 2>&1`;

like(
   $output,
   qr/Providing MySQL password on the command line interface is insecure/m,
   "Warning is printed when -p option is used after --"
);

cleanup();

# Test 6: Check that warning IS printed when --password= secret123 (with space)
$output = `$trunk/bin/pt-stalk --system-only --no-stalk --iterations=1 --run-time=1 --log=$log_file --pid=$pid_file --dest=$dest -- "--password= secret123" 2>&1`;

like(
   $output,
   qr/Providing MySQL password on the command line interface is insecure/m,
   "Warning is printed when --password= secret123 (with space) is used after --"
);

cleanup();

# Test 7: Check that warning is NOT printed when --password secret123 (space separated)
$output = `$trunk/bin/pt-stalk --system-only --no-stalk --iterations=1 --run-time=1 --log=$log_file --pid=$pid_file --dest=$dest -- --password secret123 2>&1`;

unlike(
   $output,
   qr/Providing MySQL password on the command line interface is insecure/m,
   "Warning is NOT printed when --password secret123 (space separated) is used after --"
);

cleanup();

# Test 8: Check that warning is NOT printed when --paassword=secret123 (typo)
$output = `$trunk/bin/pt-stalk --system-only --no-stalk --iterations=1 --run-time=1 --log=$log_file --pid=$pid_file --dest=$dest -- --paassword=secret123 2>&1`;

unlike(
   $output,
   qr/Providing MySQL password on the command line interface is insecure/m,
   "Warning is NOT printed when --paassword=secret123 (typo) is used after --"
);

cleanup();

# Test 9: Check that warning is NOT printed when -p secret123 (space separated)
$output = `$trunk/bin/pt-stalk --system-only --no-stalk --iterations=1 --run-time=1 --log=$log_file --pid=$pid_file --dest=$dest -- -p secret123 2>&1`;

unlike(
   $output,
   qr/Providing MySQL password on the command line interface is insecure/m,
   "Warning is NOT printed when -p secret123 (space separated) is used after --"
);

cleanup();

# Test 10: Check that warning is NOT printed when --psecret123 (invalid format)
$output = `$trunk/bin/pt-stalk --system-only --no-stalk --iterations=1 --run-time=1 --log=$log_file --pid=$pid_file --dest=$dest -- --psecret123 2>&1`;

unlike(
   $output,
   qr/Providing MySQL password on the command line interface is insecure/m,
   "Warning is NOT printed when --psecret123 (invalid format) is used after --"
);

cleanup();

# Test 11: Check that warning IS printed when -password=secret123 
# (starts with -p, so if someone has password 'assword=secret123', it should warn)
$output = `$trunk/bin/pt-stalk --system-only --no-stalk --iterations=1 --run-time=1 --log=$log_file --pid=$pid_file --dest=$dest -- -password=secret123 2>&1`;

like(
   $output,
   qr/Providing MySQL password on the command line interface is insecure/m,
   "Warning IS printed when -password=secret123 is used (conservatively warns for -p pattern)"
);

cleanup();

done_testing;