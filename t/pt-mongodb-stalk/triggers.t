#!/usr/bin/env perl

# The built-in triggers against a real MongoDB server.  See mongodb.t for the
# environment variables and how to start the servers with docker compose.
# The repllag tests also need PT_TEST_MONGODB_RS_URI (a replica set primary)
# and PT_TEST_MONGODB_RS_SECONDARY_URI (one of its secondaries).

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib",
                 "$ENV{PERCONA_TOOLKIT_BRANCH}/t/pt-mongodb-stalk/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
use PtMongodbStalkTest;

my $uri = $ENV{PT_TEST_MONGODB_URI};
if ( !$uri ) {
   plan skip_all => 'PT_TEST_MONGODB_URI is not set';
}

my $primary   = $ENV{PT_TEST_MONGODB_RS_URI};
my $secondary = $ENV{PT_TEST_MONGODB_RS_SECONDARY_URI};
my $test_db   = "pt_mongodb_stalk_test";

my $run = 0;

# Stalk without collecting.  With --iterations 1 the tool exits after the
# first trigger.  A run that must not trigger is stopped once its output
# matches $until (e.g. after the first check).
sub stalk {
   my ($server, $until, @args) = @_;
   $run++;
   return run_capture_until(
      $until, 90,
      "bash", $tool,
      "--uri", $server,
      "--no-collect", "--iterations", "1", "--sleep", "0", "--interval", "1",
      "--verbose", "3",
      "--pid", "$tmpdir/stalk-$run.pid",
      @args,
   );
}

sub mongosh_eval {
   my ($server, $js) = @_;
   my $out = `mongosh --quiet '$server' --eval '$js' 2>&1`;
   chomp $out;
   return $out;
}

my $exited      = qr/exit status \d+\n\z/;
my $first_check = qr/Check results: /;
my $output;

# ###########################################################################
# status: a dot-separated path in serverStatus.
# ###########################################################################

$output = stalk($uri, $exited, "--function", "status", "--variable", "connections.current",
   "--threshold", "0", "--cycles", "2");
like($output, qr/Check results: status\(connections\.current\)=\d+, matched=yes, cycles_true=1\n/,
   "status: first matching check");
like($output, qr/Check results: status\(connections\.current\)=\d+, matched=yes, cycles_true=2\n/,
   "status: second matching check");
like($output, qr/Collect 1 triggered/, "status: --cycles 2 triggers after 2 matching checks");

# A 64-bit counter (a Long in mongosh) is printed as a number.
$output = stalk($uri, $exited, "--function", "status", "--variable", "opcounters.command",
   "--threshold", "0", "--cycles", "1");
like($output, qr/Check results: status\(opcounters\.command\)=\d+, matched=yes/,
   "status: a 64-bit counter is a number");

# The default trigger, connections.active, exists on this server.
$output = stalk($uri, $first_check, "--threshold", "1000000", "--cycles", "1");
like($output, qr/Check results: status\(connections\.active\)=\d+, matched=no/,
   "status: the default connections.active has a value");

$output = stalk($uri, $first_check, "--function", "status", "--variable", "no.such.field",
   "--threshold", "0", "--cycles", "1");
like($output, qr/Detected value is empty/, "status: a missing field is reported as empty");
like($output, qr/Check results: status\(no\.such\.field\)=, matched=no/,
   "status: a missing field never matches");

# ###########################################################################
# currentop: the number of active operations whose --variable matches --match.
# Start a slow query ($where with sleep) and match its namespace.
# ###########################################################################

$output = stalk($uri, $first_check, "--function", "currentop", "--variable", "ns",
   "--match", "^$test_db\\.slow\$", "--threshold", "0", "--cycles", "1");
like($output, qr/Check results: currentop\(ns\)=0, matched=no/,
   "currentop: no matching operations is 0");
like($output, qr/--function=currentop --variable=ns --match=\^\Q$test_db\E\\.slow\$ --threshold=/,
   "currentop: the options logged include --variable and --match");

mongosh_eval($uri, "db.getSiblingDB(\"$test_db\").slow.insertOne({x: 1})");
my $slow = fork();
die "Cannot fork: $OS_ERROR" unless defined $slow;
if ( !$slow ) {
   open STDOUT, ">", "/dev/null";
   open STDERR, ">", "/dev/null";
   exec "mongosh", "--quiet", $uri, "--eval",
      "db.getSiblingDB(\"$test_db\").slow.find({\$where: \"sleep(30000) || true\"}).toArray()";
   exit 1;
}
my $running = "";
for ( 1 .. 30 ) {
   $running = mongosh_eval($uri,
      "print(db.getSiblingDB(\"admin\").currentOp({ns: \"$test_db.slow\"}).inprog.length)");
   last if $running =~ m/^[1-9]/m;
   sleep 1;
}
like($running, qr/^[1-9]/m, "currentop: the slow query is running");

$output = stalk($uri, $exited, "--function", "currentop", "--variable", "ns",
   "--match", "^$test_db\\.slow\$", "--threshold", "0", "--cycles", "1");
like($output, qr/Check results: currentop\(ns\)=[1-9]\d*, matched=yes/,
   "currentop: counts the matching operations");
like($output, qr/Collect 1 triggered/, "currentop: triggers");

mongosh_eval($uri,
   "db.getSiblingDB(\"admin\").currentOp({ns: \"$test_db.slow\"}).inprog.forEach(o => db.killOp(o.opid))");
kill 'TERM', $slow;
waitpid($slow, 0);

# ###########################################################################
# writewait: queued writers, 0 on an idle server.
# ###########################################################################

$output = stalk($uri, $first_check, "--function", "writewait", "--threshold", "0", "--cycles", "1");
like($output, qr/Check results: writewait=0, matched=no/,
   "writewait: 0 on an idle server");

# ###########################################################################
# repllag: the lag of the most lagging secondary, in seconds.  Lock the
# secondary with fsyncLock, which stops it applying the oplog, and write to the
# primary until the lag is above the threshold.
# ###########################################################################

SKIP: {
   skip "PT_TEST_MONGODB_RS_URI and PT_TEST_MONGODB_RS_SECONDARY_URI are not set", 5
      unless $primary && $secondary;

   $output = stalk($primary, $first_check, "--function", "repllag", "--threshold", "1000", "--cycles", "1");
   like($output, qr/Check results: repllag=\d+, matched=no/,
      "repllag: a number on a replica set primary");

   my $lock = mongosh_eval($secondary, "print(db.fsyncLock().ok)");
   like($lock, qr/^1$/m, "repllag: secondary locked") or diag($lock);

   my $writer = fork();
   die "Cannot fork: $OS_ERROR" unless defined $writer;
   if ( !$writer ) {
      open STDOUT, ">", "/dev/null";
      open STDERR, ">", "/dev/null";
      exec "mongosh", "--quiet", $primary, "--eval",
         "for (let i = 0; i < 240; i++) { db.getSiblingDB(\"$test_db\").t.insertOne({i}); sleep(250); }";
      exit 1;
   }

   $output = stalk($primary, $exited, "--function", "repllag", "--threshold", "3", "--cycles", "1");

   kill 'TERM', $writer;
   waitpid($writer, 0);
   mongosh_eval($secondary, "db.fsyncUnlock()");

   my ($lag) = $output =~ m/Check results: repllag=(\d+), matched=yes/;
   ok(defined $lag && $lag > 3, "repllag: the lag of the locked secondary is above the threshold")
      or diag($output);
   like($output, qr/Collect 1 triggered/, "repllag: triggers");

   my $unlocked = mongosh_eval($secondary, "print(db.currentOp().fsyncLock ? 1 : 0)");
   is($unlocked, "0", "repllag: secondary unlocked");
}

# repllag on a server that is not in a replica set has no value.
$output = stalk($uri, $first_check, "--function", "repllag", "--threshold", "0", "--cycles", "1");
if ( $output =~ m/repllag=\d/ ) {
   pass("repllag: the server is in a replica set");
}
else {
   like($output, qr/Detected value is empty/, "repllag: no value outside a replica set");
}

# Never leave the secondary locked, the slow query running, or the test
# database behind.
END {
   if ( $secondary ) {
      mongosh_eval($secondary, "while (db.currentOp().fsyncLock) db.fsyncUnlock()");
   }
   if ( $uri ) {
      mongosh_eval($uri,
         "db.getSiblingDB(\"admin\").currentOp({ns: \"$test_db.slow\"}).inprog.forEach(o => db.killOp(o.opid))");
      mongosh_eval($uri, "db.getSiblingDB(\"$test_db\").dropDatabase()");
   }
   if ( $primary ) {
      mongosh_eval($primary, "db.getSiblingDB(\"$test_db\").dropDatabase()");
   }
}

done_testing;
