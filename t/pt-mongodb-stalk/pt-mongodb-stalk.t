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
like($output, qr/Run immediately without stalking/, "--help prints inline examples");

my $dest = "$tmpdir/collect";
($status, $output) = run_capture(
   "bash", $tool,
   "--host", "localhost",
   "--port", "27017",
   "--user", "admin",
   "--password", "admin",
   "--authenticationDatabase", "admin",
   "--no-stalk",
   "--iterations", "1",
   "--run-time", "1",
   "--sleep-collect", "1",
   "--sleep", "1",
   "--disk-pct-free", "1",
   "--disk-bytes-free", "1",
   "--dest", $dest,
   "--pid", "$dest/pt-mongodb-stalk.pid",
);

is($status, 0, "--no-stalk collection exits 0")
   or diag($output, `find "$dest" -maxdepth 1 -type f -print 2>/dev/null`);

ok(-f "$dest/trigger", "creates trigger file");
ok(-f "$dest/heartbeat", "creates heartbeat file");
ok(-f "$dest/log", "creates log file");

is(glob_count("$dest/*-serverStatus.json"), 1, "collects serverStatus once");
is(glob_count("$dest/*-currentOp.json"),    1, "collects currentOp once");
is(glob_count("$dest/*-mongostat.txt"),     1, "collects mongostat once");
is(glob_count("$dest/*-mongotop.txt"),      1, "collects mongotop once");
is(glob_count("$dest/*-ps.txt"),            1, "collects ps once");
is(glob_count("$dest/*-pidstat_mongod.txt"), 1, "collects process pidstat with mongod label");

my @mongotop_err = glob("$dest/*-mongotop.err");
is(scalar @mongotop_err, 1, "keeps non-empty mongotop stderr");
like(slurp_file($mongotop_err[0]), qr/connected to: mongodb:\/\/localhost:27017/, "mongotop stderr keeps connection banner");

my $mongosh_log = slurp_file($ENV{MONGOSH_LOG});
like(
   $mongosh_log,
   qr/currentOp: 1, active: true, idleConnections: false, allUsers: true/,
   "currentOp command includes allUsers"
);

ok(!-e "$dest/topology",   "does not write topology file");
ok(!-e "$dest/disk-space", "does not write disk-space file");

done_testing;
