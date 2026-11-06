#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

use PerconaTest;

my $tool    = "$trunk/bin/pt-mongodb-stalk";
my $tmpdir  = tempdir("pt-mongodb-stalk.XXXXXX", TMPDIR => 1, CLEANUP => 1);
my $fakebin = "$tmpdir/bin";
my $run_no  = 0;

make_path($fakebin);

sub write_fake_cmd {
   my ($name, $body) = @_;
   my $file = "$fakebin/$name";
   open my $fh, ">", $file or die "Cannot write $file: $OS_ERROR";
   print {$fh} $body;
   close $fh;
   chmod 0755, $file or die "Cannot chmod $file: $OS_ERROR";
   return $file;
}

# Like run_capture, but send SIGTERM to the command after $timeout seconds,
# for runs that only stop on a signal.
sub run_capture_timeout {
   my ($timeout, @cmd) = @_;
   $run_no++;
   my $out = "$tmpdir/run-$run_no.out";
   my $pid = fork();
   die "Cannot fork: $OS_ERROR" unless defined $pid;

   if ( !$pid ) {
      open STDOUT, ">", $out or die "Cannot redirect stdout: $OS_ERROR";
      open STDERR, ">&", \*STDOUT or die "Cannot redirect stderr: $OS_ERROR";
      exec @cmd;
      die "Cannot exec $cmd[0]: $OS_ERROR";
   }

   my $waited = 0;
   while ( waitpid($pid, 1) == 0 ) {  # 1 = WNOHANG
      if ( $waited++ == $timeout * 10 ) {
         kill 'TERM', $pid;
      }
      select(undef, undef, undef, 0.1);
   }
   return slurp_file($out);
}

sub run_capture {
   my (@cmd) = @_;
   $run_no++;
   my $out = "$tmpdir/run-$run_no.out";
   my $pid = fork();
   die "Cannot fork: $OS_ERROR" unless defined $pid;

   if ( !$pid ) {
      open STDOUT, ">", $out or die "Cannot redirect stdout: $OS_ERROR";
      open STDERR, ">&", \*STDOUT or die "Cannot redirect stderr: $OS_ERROR";
      exec @cmd;
      die "Cannot exec $cmd[0]: $OS_ERROR";
   }

   waitpid($pid, 0);
   my $status = $CHILD_ERROR >> 8;
   my $text   = slurp_file($out);
   return ($status, $text);
}

sub glob_count {
   my ($pattern) = @_;
   my @files = glob($pattern);
   return scalar @files;
}

# mongosh is run as "mongosh --nodb --quiet <script>.js".  MONGOSH_ARGS_LOG
# records only the command lines; MONGOSH_LOG also records the scripts.
write_fake_cmd("mongosh", <<'SH');
#!/usr/bin/env bash
script_file="${@: -1}"
script="$(cat "$script_file" 2>/dev/null)"
[ -n "${MONGOSH_ARGS_LOG:-}" ] && printf '%s\n' "$*" >> "$MONGOSH_ARGS_LOG"
[ -n "${MONGOSH_LOG:-}" ] && printf '%s\n%s\n' "$*" "$script" >> "$MONGOSH_LOG"
# The collection scripts write their files themselves; act them out.
p_dir="$(sed -n "s/^const P_DIR = '\(.*\)';\$/\1/p" "$script_file")"
p_prefix="$(sed -n "s/^const P_PREFIX = '\(.*\)';\$/\1/p" "$script_file")"
p_count="$(sed -n 's/^const P_COUNT = \([0-9]*\);$/\1/p' "$script_file")"
p_tmpdir="$(sed -n "s/^const P_TMPDIR = '\(.*\)';\$/\1/p" "$script_file")"
case "$script" in
   *"__try('hostInfo'"*)
      printf 'TS 1.0 2026-01-01 00:00:00\n{"hostname": "fake"}\n' >> "$p_dir/$p_prefix-hostinfo"
      printf '4242|\n' > "$p_tmpdir/mongo-server"
      exit 0
      ;;
   *"for (let i = 0; i < P_COUNT"*)
      i=0
      while [ "$i" -lt "$p_count" ]; do
         printf 'TS 1.0 2026-01-01 00:00:00\n{"connections": {"active": 2}}\n' >> "$p_dir/$p_prefix-serverstatus"
         printf '+---+\n| Variable_name | Value |\n+---+\n| connections.active | 2 |\n+---+\n\n' >> "$p_dir/$p_prefix-serverstatus-ext"
         printf 'TS 1.0 2026-01-01 00:00:00\n{"inprog": []}\n' >> "$p_dir/$p_prefix-currentop"
         i=$((i + 1))
      done
      exit 0
      ;;
esac
case "$script" in
   *"__serverStatus.process"*)
      printf 'mongod||PRIMARY|rs0\n'
      ;;
   *"currentOp: 1"*)
      printf '{"inprog":[]}\n'
      ;;
   *"serverStatus: 1"*)
      printf '{"process":"mongod","connections":{"current":5,"active":2},"globalLock":{"currentQueue":{"writers":0}}}\n'
      ;;
   *"replSetGetStatus: 1"*)
      printf '{"members":[]}\n'
      ;;
esac
exit 0
SH

# mongostat and mongotop record their command line in MONGO_TOOLS_LOG and the
# contents of their --config file in MONGO_TOOLS_CONFIG_LOG.
my $fake_mongo_tool = <<'SH';
#!/usr/bin/env bash
[ -n "${MONGO_TOOLS_LOG:-}" ] && printf '%s\n' "$(basename "$0") $*" >> "$MONGO_TOOLS_LOG"
for arg in "$@"; do
   case "$arg" in
      --config=*) [ -n "${MONGO_TOOLS_CONFIG_LOG:-}" ] && cat "${arg#--config=}" >> "$MONGO_TOOLS_CONFIG_LOG" ;;
   esac
done
echo "2026-05-14T00:00:00.000+0000	connected to: mongodb://localhost:27017/" >&2
SH

write_fake_cmd("mongostat", $fake_mongo_tool . <<'SH');
echo "insert query update delete getmore command dirty used flushes vsize res qrw arw net_in net_out conn time"
echo "0 0 0 0 0 1|0 0.0% 1.0% 0 100M 50M 0|0 0|0 1k 2k 1 00:00:00"
SH

write_fake_cmd("mongotop", $fake_mongo_tool . <<'SH');
echo "ns total read write"
echo "admin.system.version 1ms 1ms 0ms"
SH

write_fake_cmd("df", <<'SH');
#!/usr/bin/env bash
cat <<EOF
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/fake 1000000 1 999999 1% /tmp
EOF
SH

write_fake_cmd("lsof", <<'SH');
#!/usr/bin/env bash
echo "mongod 4242 user 10u IPv4 1 0t0 TCP localhost:27017 (LISTEN)"
SH

write_fake_cmd("pidof", <<'SH');
#!/usr/bin/env bash
exit 1
SH

write_fake_cmd("ps", <<'SH');
#!/usr/bin/env bash
echo "USER PID %CPU %MEM COMMAND"
echo "mongodb 4242 0.0 1.0 mongod --port 27017"
echo "admin 4343 0.0 0.1 bash pt-mongodb-stalk --user admin --password S3cretPw --port 27017"
echo "admin 4344 0.0 0.1 mongosh mongodb://admin:S3cretPw@localhost:27017/admin"
SH

write_fake_cmd("journalctl", <<'SH');
#!/usr/bin/env bash
echo "journal entry: $*"
SH

write_fake_cmd("pmap", <<'SH');
#!/usr/bin/env bash
[ "$1" = "--help" ] && { echo "  -x, --extended"; exit 0; }
echo "pmap $*"
SH

for my $cmd (qw(vmstat iostat mpstat top pidstat sysctl netstat)) {
   write_fake_cmd($cmd, <<"SH");
#!/usr/bin/env bash
echo "$cmd sample \$*"
SH
}

make_path("$tmpdir/tmp");
local $ENV{PATH}                   = "$fakebin:$ENV{PATH}";
local $ENV{TMPDIR}                 = "$tmpdir/tmp";
local $ENV{MONGOSH_LOG}            = "$tmpdir/mongosh.log";
local $ENV{MONGOSH_ARGS_LOG}       = "$tmpdir/mongosh-args.log";
local $ENV{MONGO_TOOLS_LOG}        = "$tmpdir/mongo-tools.log";
local $ENV{MONGO_TOOLS_CONFIG_LOG} = "$tmpdir/mongo-tools-config.log";
local $ENV{PTDEBUG}                = "";

my ($status, $output) = run_capture("bash", $tool, "--help");
is($status, 0, "--help exits 0");
like($output, qr/Command line options:/, "--help lists the options");
like($output, qr/Options and values after processing arguments:/, "--help prints option values");
like($output, qr/--variable\s+connections\.active\n/, "default --variable is connections.active");
like($output, qr/--threshold\s+25\n/, "default --threshold is 25");
like($output, qr/--verbose\s+2\n/, "default --verbose is 2");

my $password = 'S3cretPw';
my $dest = "$tmpdir/collect";
my @common_args = (
   "--host", "localhost",
   "--port", "27017",
   "--user", "admin",
   "--password", $password,
   "--authenticationDatabase", "admin",
   "--no-stalk",
   "--run-time", "1",
   "--sleep-collect", "1",
   "--disk-pct-free", "1",
   "--disk-bytes-free", "1",
);

sub prefixes_in {
   my ($dir) = @_;
   my %prefixes;
   for my $file ( glob("$dir/*-*") ) {
      my ($prefix) = $file =~ m{/([^/]+?)-[^/]+$};
      $prefixes{$prefix}++ if $prefix;
   }
   return sort keys %prefixes;
}

($status, $output) = run_capture(
   "bash", $tool, @common_args,
   "--iterations", "1",
   "--sleep", "1",
   "--dest", $dest,
   "--pid", "$tmpdir/pt-mongodb-stalk.pid",
);

is($status, 0, "--no-stalk collection exits 0")
   or diag($output, `find "$dest" -maxdepth 1 -type f -print 2>/dev/null`);

my @prefixes = prefixes_in($dest);
is(scalar @prefixes, 1, "all files of one collection share one prefix")
   or diag(join("\n", glob("$dest/*")));
like($prefixes[0] || '', qr/^\d{4}(?:_\d{2}){5}$/, "default prefix is a timestamp");
my $p = "$dest/" . ($prefixes[0] || 'none');

ok(-f "$p-trigger",    "creates <prefix>-trigger");
ok(-f "$p-output",     "creates <prefix>-output");
ok(-f "$p-hostname",   "creates <prefix>-hostname");
ok(-f "$p-disk-space", "creates <prefix>-disk-space");
ok(-f "$p-hostinfo",         "collects the metadata once");
ok(-f "$p-serverstatus",     "collects serverStatus");
ok(-f "$p-serverstatus-ext", "collects serverStatus for pt-mext");
ok(-f "$p-currentop",        "collects currentOp");
ok(-f "$p-mongostat",      "collects mongostat");
ok(-f "$p-mongotop",       "collects mongotop");
ok(-f "$p-ps",             "collects ps");
ok(-f "$p-pidstat_mongod", "collects process pidstat with mongod label");

# System data with pt-stalk's file names and formats.
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
SKIP: {
   skip "no /proc/diskstats", 2 unless -r "/proc/diskstats";
   like(slurp_file("$p-diskstats"), qr/\ATS \d+/, "diskstats starts with a TS line");
   ok(-f "$p-meminfo", "collects meminfo");
}

ok(!-e "$dest/trigger",   "no shared trigger file");
ok(!-e "$dest/log",       "no shared log file");
ok(!-e "$dest/heartbeat", "no heartbeat file");
is(glob_count("$dest/*.err"), 0, "no .err files");

like(slurp_file("$p-trigger"), qr/pt-mongodb-stalk ran with/, "trigger file records the options");
like(slurp_file("$p-output"), qr/connected to: mongodb:\/\/localhost:27017/,
   "command stderr goes to <prefix>-output");

my $mongosh_log = slurp_file($ENV{MONGOSH_LOG});
like($mongosh_log, qr/^const P_COUNT = 1;$/m, "one sample for --run-time 1 --sleep-collect 1");
like($mongosh_log, qr/^const P_REPLSET = true;$/m,
   "replica set detected when the cluster role is empty");
like(
   $mongosh_log,
   qr/currentOp: 1, active: true, idleConnections: false, allUsers: true/,
   "currentOp command includes allUsers"
);

# Credentials: never on a command line, never in the collected files.
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

like(slurp_file("$p-journal"), qr/journal entry: --no-pager --since \@\d+/,
   "collects the system journal since a timestamp");

my @tmp_left = glob("$tmpdir/tmp/*");
is_deeply(\@tmp_left, [], "temporary directory with the connection files is removed");

# Without --user, no authSource is added: mongostat and mongotop would try to
# authenticate and fail.
unlink $ENV{MONGO_TOOLS_CONFIG_LOG};
my $dest_noauth = "$tmpdir/collect-noauth";
($status, $output) = run_capture(
   "bash", $tool,
   "--host", "localhost", "--port", "27017",
   "--no-stalk", "--run-time", "1", "--sleep-collect", "1",
   "--disk-pct-free", "1", "--disk-bytes-free", "1",
   "--iterations", "1", "--sleep", "0",
   "--dest", $dest_noauth,
   "--pid", "$tmpdir/pt-mongodb-stalk-noauth.pid",
);
is($status, 0, "collection without --user exits 0") or diag($output);
is(slurp_file($ENV{MONGO_TOOLS_CONFIG_LOG}), qq{uri: "mongodb://localhost:27017/"\nuri: "mongodb://localhost:27017/"\n},
   "without --user, the URI has no credentials and no authSource");

# --variable is quoted for JavaScript.
# The field does not exist, so the trigger never matches; stop after 3 seconds.
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

# --prefix: every file of every collection uses the given prefix.
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

# --retention-count: only the newest N collections are kept, and files that
# are not collections (here the PID file) are left alone.
my $dest_ret = "$tmpdir/collect-retention";
($status, $output) = run_capture(
   "bash", $tool, @common_args,
   "--iterations", "4",
   "--sleep", "1",
   "--retention-count", "2",
   "--dest", $dest_ret,
   "--pid", "$dest_ret/pt-mongodb-stalk.pid",
);
is($status, 0, "--retention-count collection exits 0") or diag($output);
my @kept = grep { $_ ne 'pt' } prefixes_in($dest_ret);
is(scalar @kept, 2, "--retention-count 2 keeps 2 collections")
   or diag(join("\n", glob("$dest_ret/*")));
ok(-f "$dest_ret/$kept[$_]-serverstatus", "kept collection $_ is complete") for 0..$#kept;

# Options with uppercase letters cannot be given as --name=value.
($status, $output) = run_capture("bash", $tool, "--authenticationDatabase=admin", "--sslCAFile=/tmp/ca.pem", "--no-stalk");
is($status, 1, "--authenticationDatabase=value exits 1");
like($output, qr/Use '--authenticationDatabase <value>' instead of '--authenticationDatabase=<value>'/,
   "--authenticationDatabase=value prints a specific error");
like($output, qr/Use '--sslCAFile <value>' instead of '--sslCAFile=<value>'/,
   "every uppercase option with = is reported");
unlike($output, qr/Unknown option/, "no generic unknown option error");

($status, $output) = run_capture("bash", $tool, "--authenticationDatabase", "admin", "--port=27017", "--help");
is($status, 0, "--authenticationDatabase value and lowercase --name=value are accepted") or diag($output);

my $conf = "$tmpdir/pt-mongodb-stalk.conf";
open my $conf_fh, ">", $conf or die "Cannot write $conf: $OS_ERROR";
print {$conf_fh} "port=27017\nauthenticationDatabase = admin\n";
close $conf_fh;
($status, $output) = run_capture("bash", $tool, "--config", $conf, "--help");
is($status, 1, "uppercase option in --config file exits 1");
like($output, qr/\Q$conf\E line 2: option 'authenticationDatabase' cannot be set in a config file/,
   "uppercase option in --config file prints a specific error");

done_testing;
