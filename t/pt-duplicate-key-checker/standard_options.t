#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-duplicate-key-checker";

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-duplicate-key-checker -F $cnf -h 127.1";
my $pid_file = "/tmp/pt-dupe-key-test.pid";

diag(`rm -f $pid_file >/dev/null`);

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################

diag(`touch $pid_file`);

$output = `$cmd -d issue_295 --pid $pid_file 2>&1`;
like(
   $output,
   qr{PID file $pid_file exists},
   'Dies if PID file already exists (issue 391)'
);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -f $pid_file >/dev/null`);
exit;
