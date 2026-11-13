#!/usr/bin/env perl

# One collection: the file layout, the MongoDB and system data, and how the
# credentials are handled.  Uses the fake commands; no MongoDB server.

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

use_fake_commands();

my ($status, $output);
my $dest = "$tmpdir/collect";

($status, $output) = run_capture(
   "bash", $tool, @common_args,
   "--iterations", "1",
   "--sleep", "1",
   "--dest", $dest,
   "--pid", "$tmpdir/pt-mongodb-stalk.pid",
);

is($status, 0, "--no-stalk collection exits 0")
   or diag($output, `find "$dest" -maxdepth 1 -type f -print 2>/dev/null`);

# ###########################################################################
# File layout, as pt-stalk's.
# ###########################################################################

my @prefixes = prefixes_in($dest);
is(scalar @prefixes, 1, "all files of one collection share one prefix")
   or diag(join("\n", glob("$dest/*")));
like($prefixes[0] || '', qr/^\d{4}(?:_\d{2}){5}$/, "default prefix is a timestamp");
my $p = "$dest/" . ($prefixes[0] || 'none');

ok(-f "$p-trigger",    "creates <prefix>-trigger");
ok(-f "$p-output",     "creates <prefix>-output");
ok(-f "$p-hostname",   "creates <prefix>-hostname");
ok(-f "$p-disk-space", "creates <prefix>-disk-space");

ok(!-e "$dest/trigger",   "no shared trigger file");
ok(!-e "$dest/log",       "no shared log file");
ok(!-e "$dest/heartbeat", "no heartbeat file");
my @err_files = glob("$dest/*.err");
is(scalar @err_files, 0, "no .err files");

like(slurp_file("$p-trigger"), qr/pt-mongodb-stalk ran with/, "trigger file records the options");
like(slurp_file("$p-trigger"), qr/ran with --function=status --variable=connections\.active --threshold=/,
   "trigger file records --variable for status, and no --match, which only currentop uses");
like(slurp_file("$p-trigger"), qr/Collect 1 finished in \d+s$/m, "trigger file records when the collection ends");
like(slurp_file("$p-output"), qr/connected to: mongodb:\/\/localhost:27017/,
   "command stderr goes to <prefix>-output");

# ###########################################################################
# MongoDB data.
# ###########################################################################

ok(-f "$p-hostinfo",         "collects the metadata once");
ok(-f "$p-serverstatus",     "collects serverStatus");
ok(-f "$p-serverstatus-ext", "collects serverStatus for pt-mext");
ok(-f "$p-currentop",        "collects currentOp");
ok(-f "$p-mongostat",        "collects mongostat");
ok(-f "$p-mongotop",         "collects mongotop");

my $mongosh_log = slurp_file($ENV{MONGOSH_LOG});
like($mongosh_log, qr/^const P_COUNT = 1;$/m, "one sample for --run-time 1 --sleep-collect 1");
my @replset_checks = $mongosh_log =~ m/__replset\(\)/g;
ok(scalar @replset_checks >= 2, "the metadata and time-series scripts check for a replica set themselves");
like($mongosh_log, qr/currentOp: 1, active: true\}/, "currentOp command asks for the active operations");
unlike($mongosh_log, qr/idleConnections|allUsers/,
   "currentOp command has no \$currentOp stage options, which the command reads as filters");

# ###########################################################################
# System data, with pt-stalk's file names and formats.
# ###########################################################################

ok(-f "$p-ps",             "collects ps");
ok(-f "$p-pidstat_mongod", "collects process pidstat with mongod label");
like(slurp_file("$p-pmap"), qr/^pmap -x 4242$/m, "pmap -x for the server's PID");
like(slurp_file("$p-lsof"), qr/mongod 4242/, "lsof for the server's PID");
like(slurp_file("$p-sysctl"), qr/^sysctl sample -a$/m, "sysctl -a");
like(slurp_file("$p-vmstat"), qr/^vmstat sample 1 1$/m, "vmstat --sleep-collect count");
like(slurp_file("$p-vmstat-overall"), qr/^vmstat sample 1 2$/m, "vmstat --run-time 2");
like(slurp_file("$p-iostat"), qr/^iostat sample -dx 1 1$/m, "iostat -dx");
like(slurp_file("$p-iostat-overall"), qr/^iostat sample -dx 1 2$/m, "iostat -dx --run-time 2");
like(slurp_file("$p-mpstat-overall"), qr/^mpstat sample -P ALL 1 1$/m, "mpstat -P ALL --run-time 1");
like(slurp_file("$p-pidstat_mongod"), qr/^pidstat sample -urdwt -h -p 4242 1 1$/m,
   "pidstat for the server's PID");
for my $name ( qw(df netstat netstat_s) ) {
   like(slurp_file("$p-$name"), qr/\ATS \d+\.\S+ \d{4}-\d\d-\d\d \d\d:\d\d:\d\d\n/,
      "$name starts with a TS line");
}
like(slurp_file("$p-netstat"), qr/^netstat sample -antp$/m, "netstat -antp");
like(slurp_file("$p-journal"), qr/journal entry: --no-pager --since \@\d+/,
   "collects the system journal since a timestamp");
SKIP: {
   skip "no /proc/diskstats", 2 unless -r "/proc/diskstats";
   like(slurp_file("$p-diskstats"), qr/\ATS \d+/, "diskstats starts with a TS line");
   ok(-f "$p-meminfo", "collects meminfo");
}

# ###########################################################################
# Credentials: never on a command line, never in the collected files.
# ###########################################################################

like($mongosh_log, qr{connect\('mongodb://admin:S3cretPw\@localhost:27017/\?authSource=admin'\)},
   "mongosh connects using the URI written in its script");
my $mongosh_args = slurp_file($ENV{MONGOSH_ARGS_LOG});
like($mongosh_args, qr/^--nodb --quiet \S+\.js$/m, "mongosh runs a script file");
unlike($mongosh_args, qr/\Q$password\E/, "password not on the mongosh command line");

my $tools_log = slurp_file($ENV{MONGO_TOOLS_LOG});
like($tools_log, qr/^mongostat --config=\S+ --rowcount 1 1$/m, "mongostat gets only --config");
like($tools_log, qr/^mongotop --config=\S+ --rowcount 1 1$/m,  "mongotop gets only --config");
unlike($tools_log, qr/\Q$password\E/, "password not on the mongostat/mongotop command line");
like(slurp_file($ENV{MONGO_TOOLS_CONFIG_LOG}),
   qr{^uri: "mongodb://admin:S3cretPw\@localhost:27017/\?authSource=admin"$}m,
   "mongostat/mongotop get the URI from the --config file");

my $ps = slurp_file("$p-ps");
like($ps, qr/--password \*\*\* --port 27017/, "ps output hides --password");
like($ps, qr{mongodb://admin:\*\*\*\@localhost}, "ps output hides URI passwords");
my @leaks = grep { slurp_file($_) =~ m/\Q$password\E/ } glob("$dest/*");
is_deeply(\@leaks, [], "password not in any collected file");

# A password with spaces and regex characters is hidden whole, not only up to
# the first space.
{
   my $spaced = 'two words.* S3c';
   local $ENV{FAKE_PS_PASSWORD} = $spaced;
   my ($status, $output, $sp) = collect_with("--password", $spaced);
   is($status, 0, "collection with a password with spaces exits 0") or diag($output);
   my $ps = slurp_file("$sp-ps");
   like($ps, qr/--password \*\*\* --port 27017$/m, "ps output hides a password with spaces");
   unlike($ps, qr/words|S3c/, "no part of the password with spaces is left");
   ok(!-e "$tmpdir/tmp/secrets", "the file with the passwords to hide is removed");
}

my @tmp_left = glob("$tmpdir/tmp/*");
is_deeply(\@tmp_left, [], "temporary directory with the connection files is removed");

# Without --user, no authSource is added: mongostat and mongotop would try to
# authenticate and fail.
unlink $ENV{MONGO_TOOLS_CONFIG_LOG};
($status, $output) = run_capture(
   "bash", $tool,
   "--host", "localhost", "--port", "27017",
   "--no-stalk", "--run-time", "1", "--sleep-collect", "1",
   "--disk-pct-free", "1", "--disk-bytes-free", "1",
   "--iterations", "1", "--sleep", "0",
   "--dest", "$tmpdir/collect-noauth",
   "--pid", "$tmpdir/pt-mongodb-stalk-noauth.pid",
);
is($status, 0, "collection without --user exits 0") or diag($output);
is(slurp_file($ENV{MONGO_TOOLS_CONFIG_LOG}), qq{uri: "mongodb://localhost:27017/"\nuri: "mongodb://localhost:27017/"\n},
   "without --user, the URI has no credentials and no authSource");
unlike($output, qr/Providing the MongoDB password on the command line is insecure/,
   "no password warning without a password");

# --variable is quoted for JavaScript.  The field does not exist, so the
# trigger never matches; stop after 3 seconds.
unlink $ENV{MONGOSH_LOG};
$output = run_capture_timeout(
   3,
   "bash", $tool,
   "--host", "localhost", "--port", "27017",
   "--variable", "it's.a\\path",
   "--no-collect", "--cycles", "1",
   "--pid", "$tmpdir/pt-mongodb-stalk-var.pid",
);
like(slurp_file($ENV{MONGOSH_LOG}), qr/for \(const __part of 'it\\'s\.a\\\\path'\.split/,
   "--variable is quoted in the mongosh script");

# ###########################################################################
# --prefix: every file of every collection uses the given prefix.
# ###########################################################################

my $dest_prefix = "$tmpdir/collect-prefix";
($status, $output) = run_capture(
   "bash", $tool, @common_args,
   "--iterations", "2",
   "--sleep", "1",
   "--prefix", "MYPREFIX",
   "--dest", $dest_prefix,
   "--pid", "$tmpdir/pt-mongodb-stalk-prefix.pid",
);
is($status, 0, "--prefix collection exits 0") or diag($output);
is_deeply([prefixes_in($dest_prefix)], ["MYPREFIX"], "--prefix is used for every file")
   or diag(join("\n", glob("$dest_prefix/*")));
my @triggers = slurp_file("$dest_prefix/MYPREFIX-trigger") =~ m/pt-mongodb-stalk ran with/g;
is(scalar @triggers, 2, "--prefix appends both collections to the same files");

done_testing;
