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

write_fake_cmd("mongosh", <<'SH');
#!/usr/bin/env bash
[ -n "${MONGOSH_LOG:-}" ] && printf '%s\n' "$*" >> "$MONGOSH_LOG"
case "$*" in
   *"__serverStatus.process"*)
      printf 'mongod\tshard\tPRIMARY\trs0\n'
      ;;
   *"currentOp: 1"*)
      printf '{"inprog":[]}\n'
      ;;
   *"serverStatus: 1"*)
      printf '{"process":"mongod","connections":{"current":5},"globalLock":{"currentQueue":{"writers":0}}}\n'
      ;;
   *"replSetGetStatus: 1"*)
      printf '{"members":[]}\n'
      ;;
esac
exit 0
SH

write_fake_cmd("mongostat", <<'SH');
#!/usr/bin/env bash
echo "insert query update delete getmore command dirty used flushes vsize res qrw arw net_in net_out conn time"
echo "0 0 0 0 0 1|0 0.0% 1.0% 0 100M 50M 0|0 0|0 1k 2k 1 00:00:00"
echo "2026-05-14T00:00:00.000+0000	connected to: mongodb://localhost:27017/" >&2
SH

write_fake_cmd("mongotop", <<'SH');
#!/usr/bin/env bash
echo "ns total read write"
echo "admin.system.version 1ms 1ms 0ms"
echo "2026-05-14T00:00:00.000+0000	connected to: mongodb://localhost:27017/" >&2
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
SH

for my $cmd (qw(vmstat iostat mpstat top pidstat)) {
   write_fake_cmd($cmd, <<"SH");
#!/usr/bin/env bash
echo "$cmd sample"
SH
}

local $ENV{PATH}        = "$fakebin:$ENV{PATH}";
local $ENV{MONGOSH_LOG} = "$tmpdir/mongosh.log";
local $ENV{PTDEBUG}     = "";

my ($status, $output) = run_capture("bash", $tool, "--help");
is($status, 0, "--help exits 0");
like($output, qr/Command line options:/, "--help lists the options");
like($output, qr/Options and values after processing arguments:/, "--help prints option values");

my $dest = "$tmpdir/collect";
my @common_args = (
   "--host", "localhost",
   "--port", "27017",
   "--user", "admin",
   "--password", "admin",
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
ok(-f "$p-serverstatus",   "collects serverStatus");
ok(-f "$p-currentop",      "collects currentOp");
ok(-f "$p-mongostat",      "collects mongostat");
ok(-f "$p-mongotop",       "collects mongotop");
ok(-f "$p-ps",             "collects ps");
ok(-f "$p-pidstat_mongod", "collects process pidstat with mongod label");

ok(!-e "$dest/trigger",   "no shared trigger file");
ok(!-e "$dest/log",       "no shared log file");
ok(!-e "$dest/heartbeat", "no heartbeat file");
is(glob_count("$dest/*.err"), 0, "no .err files");

like(slurp_file("$p-trigger"), qr/pt-mongodb-stalk ran with/, "trigger file records the options");
like(slurp_file("$p-output"), qr/connected to: mongodb:\/\/localhost:27017/,
   "command stderr goes to <prefix>-output");

my $mongosh_log = slurp_file($ENV{MONGOSH_LOG});
like(
   $mongosh_log,
   qr/currentOp: 1, active: true, idleConnections: false, allUsers: true/,
   "currentOp command includes allUsers"
);

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
