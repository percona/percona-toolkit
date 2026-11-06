#!/usr/bin/env perl

# Tests pt-mongodb-stalk against a real MongoDB server.  Set
# PT_TEST_MONGODB_URI to the server to use, for example
# mongodb://127.0.0.1:27017/, and make mongosh, mongostat and mongotop
# available in PATH.  The replica set checks run when the server is a
# replica set member.

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;

use PerconaTest;

my $uri = $ENV{PT_TEST_MONGODB_URI};
if ( !$uri ) {
   plan skip_all => 'PT_TEST_MONGODB_URI is not set';
}

my $tool   = "$trunk/bin/pt-mongodb-stalk";
my $tmpdir = tempdir("pt-mongodb-stalk.XXXXXX", TMPDIR => 1, CLEANUP => 1);
my $dest   = "$tmpdir/collect";

my $output = `bash $tool --uri '$uri' --no-stalk --iterations 1 --run-time 3 --sleep-collect 1 --sleep 0 --disk-pct-free 1 --dest $dest --pid $tmpdir/pid 2>&1`;
is($CHILD_ERROR >> 8, 0, "collection exits 0") or diag($output);

my ($trigger) = glob("$dest/*-trigger");
ok($trigger, "collection written") or BAIL_OUT("No collection in $dest");
(my $p = $trigger) =~ s/-trigger$//;

# Split a "TS line + JSON" file into its samples.
sub samples {
   my ($file) = @_;
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

for my $name ( qw(hostinfo buildinfo cmdlineopts parameters connpoolstats profiling-status) ) {
   my @s = samples("$p-$name");
   is(scalar @s, 1, "$name: one sample of TS line + JSON");
}

for my $name ( qw(serverstatus currentop) ) {
   my @s = samples("$p-$name");
   is(scalar @s, 3, "$name: 3 samples for --run-time 3 --sleep-collect 1");
}
my ($status) = samples("$p-serverstatus");
ok(!exists $status->{ok} && !exists $status->{'$clusterTime'},
   "ok and \$clusterTime removed from serverStatus");

my $ext = slurp_file("$p-serverstatus-ext");
my @tables = split /\n\n/, $ext;
is(scalar @tables, 3, "serverstatus-ext: 3 tables separated by an empty line");
my @rows = $tables[0] =~ m/^\| (\S+) +\| (\S+) +\|$/mg;
my %rows = @rows;
delete $rows{Variable_name};
ok(scalar keys %rows > 100, "serverstatus-ext has the serverStatus metrics");
is_deeply([ grep { $rows{$_} !~ m/^-?\d+$/ } sort keys %rows ], [], "all values are whole numbers");
is_deeply([ grep { m/histogram|^metrics\.commands\./i || m/[^A-Za-z0-9_.-]/ } sort keys %rows ], [],
   "no histograms, no metrics.commands, no special characters in names");
ok(exists $rows{'connections.active'}, "connections.active is a row");

my $mext = `bash $trunk/bin/pt-mext -r -- cat $p-serverstatus-ext 2>&1`;
is($CHILD_ERROR >> 8, 0, "pt-mext reads serverstatus-ext") or diag($mext);
like($mext, qr/^connections\.current\s+\d+\s+-?\d+\s+-?\d+$/m, "pt-mext shows the 3 samples side by side");

my $hello = `mongosh --quiet '$uri' --eval 'print(db.hello().setName || "")' 2>/dev/null`;
chomp $hello;
SKIP: {
   skip "not a replica set member", 4 unless $hello;
   is(scalar(samples("$p-$_")), 1, "$_: one sample") for qw(rs-conf oplog-info);
   is(scalar(samples("$p-replsetgetstatus")), 3, "replsetgetstatus: 3 samples");
   unlike(slurp_file("$p-output"), qr/^MongoDB /m, "no MongoDB command errors") or diag(slurp_file("$p-output"));
}

done_testing;
