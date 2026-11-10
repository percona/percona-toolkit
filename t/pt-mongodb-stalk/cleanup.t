#!/usr/bin/env perl

# Collectors that do not finish in time are stopped with everything they
# started: the commands, not only the Bash wrappers that run them.  Uses the
# fake commands, made to hang like commands on a stalled server.

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib",
                 "$ENV{PERCONA_TOOLKIT_BRANCH}/t/pt-mongodb-stalk/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Time::HiRes qw(time);
use Test::More;

use PerconaTest;
use PtMongodbStalkTest;

use_fake_commands();

# The fake commands and their sleeps still running, from the real ps (the
# fake one in PATH lists fixed processes).  Each test uses its own sleep
# time, so it only sees its own processes.
sub left_running {
   my ($seconds) = @_;
   return grep { m/\bsleep $seconds$/ || m/\Q$fakebin\E\/mongo/ }
          split /\n/, `/bin/ps -ax -o command= 2>/dev/null`;
}

# mongosh's time-series loop and mongostat hang; mongotop and the system
# collectors finish.
{
   local $ENV{FAKE_BLOCK} = 731;
   my $start = time;
   my ($status, $output, $p) = collect_with();
   my $elapsed = time - $start;
   is($status, 0, "hanging collectors: collection exits 0") or diag($output);
   ok($elapsed < 30, "hanging collectors: the collection ends in time")
      or diag("took $elapsed seconds");
   like(slurp_file("$p-output"), qr/Killing subprocesses \d+/,
      "hanging collectors: they are killed");
   my @left = left_running(731);
   is_deeply(\@left, [], "hanging collectors: mongosh, mongostat and their children are not left running")
      or system("pkill -f 'sleep 731'");
}

# mongotop hangs and ignores SIGTERM: killed with SIGKILL after 5 seconds.
{
   local $ENV{FAKE_BLOCK_IGNORE_TERM} = 732;
   my ($status, $output, $p) = collect_with();
   is($status, 0, "collector ignoring SIGTERM: collection exits 0") or diag($output);
   like(slurp_file("$p-output"), qr/Subprocesses did not exit; killing them with SIGKILL/,
      "collector ignoring SIGTERM: killed with SIGKILL");
   my @left = left_running(732);
   is_deeply(\@left, [], "collector ignoring SIGTERM: mongotop and its children are not left running")
      or system("pkill -9 -f 'sleep 732'");
}

done_testing;
