#!/usr/bin/env perl

# A collection from real MongoDB servers: the JSON samples, the
# serverstatus-ext file for pt-mext, and the replica set and mongos cases.
#
# The tests run against the servers in these environment variables, and are
# skipped for the ones that are not set:
#
#   PT_TEST_MONGODB_URI                a standalone server, or any server
#   PT_TEST_MONGODB_RS_URI             a replica set primary
#   PT_TEST_MONGODB_RS_SECONDARY_URI   one of its secondaries (triggers.t)
#   PT_TEST_MONGODB_MONGOS_URI         a mongos
#
# mongosh, mongostat and mongotop must be in PATH.  The MongoDB containers in
# src/go/docker-compose.yml provide all of them.  Its setup scripts use the
# legacy mongo shell, so use an image that has it, e.g. MongoDB 4.4:
#
#   cd src/go
#   TEST_MONGODB_IMAGE=mongo:4.4 docker compose up -d standalone \
#      mongo-rs1-setup mongo-rs2-setup mongo-cnf-setup mongo-shard-setup
#
#   export PT_TEST_MONGODB_URI=mongodb://127.0.0.1:27017/
#   export PT_TEST_MONGODB_RS_URI=mongodb://127.0.0.1:17001/
#   export PT_TEST_MONGODB_RS_SECONDARY_URI=mongodb://127.0.0.1:17002/
#   export PT_TEST_MONGODB_MONGOS_URI=mongodb://127.0.0.1:17000/
#
# The replica set members are registered with their container addresses, so
# connect to each member directly as above, not with ?replicaSet=.

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib",
                 "$ENV{PERCONA_TOOLKIT_BRANCH}/t/pt-mongodb-stalk/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use JSON::PP;
use Test::More;

use PerconaTest;
use PtMongodbStalkTest;

my %servers = (
   standalone => $ENV{PT_TEST_MONGODB_URI},
   replicaset => $ENV{PT_TEST_MONGODB_RS_URI},
   mongos     => $ENV{PT_TEST_MONGODB_MONGOS_URI},
);
delete $servers{$_} for grep { !$servers{$_} } keys %servers;
if ( !%servers ) {
   plan skip_all => 'None of PT_TEST_MONGODB_URI, PT_TEST_MONGODB_RS_URI '
                  . 'and PT_TEST_MONGODB_MONGOS_URI is set';
}

# Split a "TS line + JSON" file into its samples.
sub samples {
   my ($file) = @_;
   return unless -f $file;
   my @samples;
   my $json = JSON::PP->new->allow_nonref;
   for my $chunk ( split /^(?=TS )/m, slurp_file($file) ) {
      my ($ts, $body) = $chunk =~ m/^(TS \d+\.\d{9} \d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\n(.*)\z/s
         or return;
      my $doc = eval { $json->decode($body) } or return;
      push @samples, $doc;
   }
   return @samples;
}

for my $kind ( sort keys %servers ) {
   my $uri  = $servers{$kind};
   my $dest = "$tmpdir/collect-$kind";

   my ($status, $output) = run_capture(
      "bash", $tool, "--uri", $uri,
      "--no-stalk", "--iterations", "1", "--run-time", "3", "--sleep-collect", "1",
      "--sleep", "0", "--disk-pct-free", "1",
      "--dest", $dest, "--pid", "$tmpdir/$kind.pid",
   );
   is($status, 0, "$kind: collection exits 0") or diag($output);

   my ($trigger) = glob("$dest/*-trigger");
   if ( !ok($trigger, "$kind: collection written") ) {
      diag(join("\n", glob("$dest/*")));
      next;
   }
   (my $p = $trigger) =~ s/-trigger$//;

   for my $name ( qw(hostinfo buildinfo cmdlineopts parameters connpoolstats profiling-status) ) {
      my @s = samples("$p-$name");
      is(scalar @s, 1, "$kind: $name: one sample of TS line + JSON");
   }

   for my $name ( qw(serverstatus currentop) ) {
      my @s = samples("$p-$name");
      is(scalar @s, 3, "$kind: $name: 3 samples for --run-time 3 --sleep-collect 1");
   }
   # A mongod always has some active operations (internal threads included).
   if ( $kind ne 'mongos' ) {
      my @ops = map { @{ $_->{inprog} || [] } } samples("$p-currentop");
      ok(scalar @ops > 0, "$kind: currentop lists the active operations");
   }

   my ($status_doc) = samples("$p-serverstatus");
   ok($status_doc && !exists $status_doc->{ok} && !exists $status_doc->{'$clusterTime'},
      "$kind: ok and \$clusterTime removed from serverStatus");
   is($status_doc && $status_doc->{process}, $kind eq 'mongos' ? 'mongos' : 'mongod',
      "$kind: serverStatus is from the right process");

   my @tables = split /\n\n/, slurp_file("$p-serverstatus-ext");
   is(scalar @tables, 3, "$kind: serverstatus-ext: 3 tables separated by an empty line");
   my %rows = $tables[0] =~ m/^\| (\S+) +\| (\S+) +\|$/mg;
   delete $rows{Variable_name};
   ok(scalar keys %rows > 50, "$kind: serverstatus-ext has the serverStatus metrics");
   is_deeply([ grep { $rows{$_} !~ m/^-?\d+$/ } sort keys %rows ], [],
      "$kind: all values are whole numbers");
   is_deeply([ grep { m/histogram|^metrics\.commands\./i || m/[^A-Za-z0-9_.-]/ } sort keys %rows ], [],
      "$kind: no histograms, no metrics.commands, no special characters in names");
   ok(exists $rows{'connections.current'}, "$kind: connections.current is a row");

   my $mext = `bash $trunk/bin/pt-mext -r -- cat $p-serverstatus-ext 2>&1`;
   is($CHILD_ERROR >> 8, 0, "$kind: pt-mext reads serverstatus-ext") or diag($mext);
   like($mext, qr/^connections\.current\s+\d+\s+-?\d+\s+-?\d+$/m,
      "$kind: pt-mext shows the 3 samples side by side");

   unlike(slurp_file("$p-output"), qr/^MongoDB /m, "$kind: no MongoDB command errors")
      or diag(slurp_file("$p-output"));

   if ( $kind eq 'replicaset' ) {
      is(scalar(samples("$p-$_")), 1, "$kind: $_: one sample") for qw(rs-conf oplog-info);
      is(scalar(samples("$p-replsetgetstatus")), 3, "$kind: replsetgetstatus: 3 samples");
   }
   else {
      is_deeply([ grep { -e "$p-$_" } qw(rs-conf oplog-info replsetgetstatus) ], [],
         "$kind: no replica set files");
   }
}

done_testing;
