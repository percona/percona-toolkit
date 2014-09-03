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


# to test this issue I must set a timeout in case the command doesn't come back 

eval {
   # we define an alarm signal handler
   local $SIG{'ALRM'} = sub { die "timed out\n" }; 

   # and set the alarm 'clock' to 5 seconds
   alarm(5);  

   # here's the actual command. correct bahaviour is to die with messsage "PID file <pid_file> exists"
   # Incorrect behavior is anything else, including not returning control after 5 seconds
   $output = `$cmd -d issue_295 --pid $pid_file 2>&1`;

};

if ($@) {
        if ($@ eq "timed out\n") {
                print "I timed out\n";
        }
        else {
                print "Something else went wrong: $@\n";
        }
}


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
