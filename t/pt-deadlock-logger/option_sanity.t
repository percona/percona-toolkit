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

my $output;

# #############################################################################
# Sanity tests.
# #############################################################################

# Wrong design: https://bugs.launchpad.net/percona-toolkit/+bug/1206728
#$output = `$trunk/bin/pt-deadlock-logger --dest D=test,t=deadlocks 2>&1`;
#like(
#   $output,
#   qr/No DSN was specified/,
#   'Requires source host'
#);

$output = `$trunk/bin/pt-deadlock-logger h=127.1 --dest t=deadlocks 2>&1`;
like(
   $output,
   qr/requires a 'D'/, 
   'Dest DSN requires D',
);

$output = `$trunk/bin/pt-deadlock-logger --dest D=test 2>&1`;
like(
   $output,
   qr/requires a 't'/,
   'Dest DSN requires t'
);

# #############################################################################
# Bug 1039074: Tools exit 0 on error parsing options, should exit non-zero
# #############################################################################

system("$trunk/bin/pt-deadlock-logger --i-am-the-error >/dev/null 2>&1");
my $exit_status = $CHILD_ERROR >> 8;

is(
   $exit_status,
   1,
   "Non-zero exit on option error (bug 1039074)"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
