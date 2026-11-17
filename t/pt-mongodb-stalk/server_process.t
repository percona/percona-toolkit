#!/usr/bin/env perl

# Which local process is the server: process data (pmap, gdb, strace, the
# log) and the process triggers use only the process of the server the tool
# connects to, never another mongod or mongos on this host.  Uses the fake
# commands; FAKE_PROCS lists the local processes (see samples/bin/procs.sh),
# and FAKE_SERVER_* what the server reports about itself.

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

# A real mongosh, or node, to run the tool's JavaScript; found before the fake
# commands come first in PATH.
my ($js_runner) = grep { -x $_ }
   map { my $dir = $_; map { "$dir/$_" } qw(mongosh node) }
   split /:/, $ENV{PATH};

use_fake_commands();

my ($status, $output, $p);

# ###########################################################################
# The port in serverStatus.host.  On the default port 27017 it is only the
# hostname, whose digits are not a port.
# ###########################################################################

SKIP: {
   skip "no mongosh or node to run the tool's JavaScript", 1 unless $js_runner;
   my $js = "$tmpdir/server_identity.js";
   my $lib = `bash -c '. "\$1"; printf "%s\\n" "\$MONGO_JS_LIB"' sh $tool`;
   open my $fh, ">", $js or die "Cannot write $js: $OS_ERROR";
   print $fh $lib, <<'JS';
for (const host of ['db546595409', 'db546595409:27018', 'ip-10-0-0-1.ec2.internal',
                    'node2.example.com:27019', 'mac', '']) {
   console.log(host + ' => [' + __server_identity({host: host}).port + ']');
}
console.log('no host => [' + __server_identity({}).port + ']');
JS
   close $fh;
   my @args = $js_runner =~ m{/mongosh$} ? ("--nodb", "--quiet", $js) : ($js);
   my $ports = `"$js_runner" @args 2>&1`;
   is($ports, <<'PORTS', "the port is parsed only from a :port suffix, otherwise 27017");
db546595409 => [27017]
db546595409:27018 => [27018]
ip-10-0-0-1.ec2.internal => [27017]
node2.example.com:27019 => [27019]
mac => [27017]
 => []
no host => []
PORTS
}

# ###########################################################################
# Process data for the PID the server reports.
# ###########################################################################

# The server reports PID 4242, port 27018 and its start time, and the local
# mongod with PID 4242 matches all of them.
($status, $output, $p) = collect_with("--collect-gdb");
is($status, 0, "matching server: collection exits 0") or diag($output);
like(slurp_file("$p-pmap"), qr/^pmap -x 4242$/m, "matching server: pmap of its PID");
ok(-f "$p-stacktrace", "matching server: --collect-gdb attaches to it");

# Another server with the same PID, e.g. on another host or in a container:
# the local mongod 4242 started long before it.
{
   local $ENV{FAKE_SERVER_UPTIME} = 30;
   ($status, $output, $p) = collect_with("--collect-gdb", "--collect-strace");
   is($status, 0, "PID of another server: collection exits 0") or diag($output);
   is_deeply([ grep { -e "$p-$_" } qw(pmap stacktrace strace lsof pidstat_mongod) ], [],
      "PID of another server: no process data, no gdb, no strace");
   like(slurp_file("$p-output"), qr/Not collecting process data for the server: the local mongod with PID 4242 did not start when the server did/,
      "PID of another server: the reason is logged");
   like(slurp_file("$p-output"), qr/does not run on this host; not collecting gdb or strace data/,
      "PID of another server: gdb and strace are not run");
}

# Same PID and start time, but the local mongod listens on another port.
{
   local $ENV{FAKE_SERVER_PORT} = 27019;
   ($status, $output, $p) = collect_with("--collect-gdb");
   ok(!-e "$p-stacktrace", "server on another port: --collect-gdb does not attach");
   like(slurp_file("$p-output"), qr/the local mongod with PID 4242 does not listen on the server's port 27019/,
      "server on another port: the reason is logged");
}

# No local process with the server's PID.
{
   local $ENV{FAKE_PROCS} = "";
   ($status, $output, $p) = collect_with("--collect-gdb");
   ok(!-e "$p-pmap", "no local process: no pmap");
   like(slurp_file("$p-output"), qr/no mongod or mongos with PID 4242 runs on this host/,
      "no local process: the reason is logged");
}

# ###########################################################################
# Process triggers.
# ###########################################################################

# Two local mongods: 4242 on 27017 at 5% CPU, 4343 on 27018 at 90% CPU.
local $ENV{FAKE_PROCS} = "4242:mongod:27017:1000:5 4343:mongod:27018:1000:90";

# Run a process trigger for a few checks, with no collection.
sub stalk_process_cpu {
   my (@args) = @_;
   return run_capture_timeout(
      4,
      "bash", $tool, @args,
      "--function", "process-cpu", "--threshold", "1000",
      "--interval", "1", "--no-collect", "--disk-pct-free", "1", "--verbose", "3",
      "--pid", "$tmpdir/stalk.pid",
   );
}

# --system-only does not connect: the process listening on the --uri port.
$output = stalk_process_cpu("--uri", "mongodb://localhost:27018/", "--system-only");
like($output, qr/measures the server's process, PID 4343/,
   "--system-only --uri port 27018: uses the mongod on 27018");
like($output, qr/Check results: process-cpu=90\.00/,
   "--system-only --uri port 27018: measures the mongod on 27018, not the one on 27017");
like($output, qr/--function=process-cpu --threshold=/,
   "process-cpu: the options logged have no --variable or --match, which it does not use");

$output = stalk_process_cpu("--host", "localhost", "--port", "27017", "--system-only");
like($output, qr/Check results: process-cpu=5\.00/,
   "--system-only --port 27017: measures the mongod on 27017");

# Connected: the PID the server reports, checked against the local process.
{
   local $ENV{FAKE_SERVER_PID}  = 4343;
   local $ENV{FAKE_SERVER_PORT} = 27018;
   $output = stalk_process_cpu("--uri", "mongodb://localhost:27018/");
   like($output, qr/Check results: process-cpu=90\.00/,
      "connected: measures the process the server reports");
}

# Fail clearly instead of measuring another process.
($status, $output) = run_capture(
   "bash", $tool, "--uri", "mongodb://localhost:27019/", "--system-only",
   "--function", "process-cpu", "--no-collect", "--pid", "$tmpdir/stalk.pid",
);
isnt($status, 0, "no mongod on the --uri port: exits with an error");
like($output, qr/--function process-cpu needs the MongoDB server to run on this host, but no mongod or mongos listening on port 27019 found on this host/,
   "no mongod on the --uri port: says why");

($status, $output) = run_capture(
   "bash", $tool, "--uri", "mongodb://db.example.com:27017/", "--system-only",
   "--function", "process-memory", "--no-collect", "--pid", "$tmpdir/stalk.pid",
);
isnt($status, 0, "remote --uri: exits with an error");
like($output, qr/needs the MongoDB server to run on this host, but db\.example\.com:27017 is not this host/,
   "remote --uri: says why");

{
   local $ENV{FAKE_SERVER_PID}    = 4242;
   local $ENV{FAKE_SERVER_PORT}   = 27018;
   local $ENV{FAKE_SERVER_UPTIME} = 30;
   ($status, $output) = run_capture(
      "bash", $tool, "--uri", "mongodb://localhost:27018/",
      "--function", "process-cpu", "--no-collect", "--pid", "$tmpdir/stalk.pid",
   );
   isnt($status, 0, "connected to another server with a colliding PID: exits with an error");
   like($output, qr/did not start when the server did, so it is another server/,
      "connected to another server with a colliding PID: says why");
}

done_testing;
