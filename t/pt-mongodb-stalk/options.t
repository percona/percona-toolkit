#!/usr/bin/env perl

# The collection options taken from pt-stalk: --skip-collection,
# --mongodb-only, --system-only, --collect-gdb, --collect-strace,
# --collect-tcpdump and --notify-by-email.  Uses the fake commands; no MongoDB
# server.

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

my ($status, $output, $p);

# --skip-collection
($status, $output, $p) = collect_with("--skip-collection", "mongostat,metadata");
is($status, 0, "--skip-collection exits 0") or diag($output);
like($output, qr/Providing the MongoDB password on the command line is insecure/,
   "warns when the password is on the command line");
ok(!-e "$p-mongostat", "--skip-collection mongostat skips mongostat");
ok(-f "$p-mongotop",   "--skip-collection mongostat keeps mongotop");
unlike(slurp_file($ENV{MONGO_TOOLS_LOG}), qr/^mongostat/m, "mongostat is not run");
like(slurp_file($ENV{MONGOSH_LOG}), qr/^const P_SKIP = ',mongostat,metadata,';$/m,
   "--skip-collection is passed to the mongosh scripts");

# Skipping all of serverStatus, currentOp and replSetGetStatus: the mongosh
# collection loop is not started at all.
unlink $ENV{MONGOSH_LOG};
($status, $output, $p) = collect_with("--skip-collection", "serverstatus,currentop,replsetgetstatus");
is($status, 0, "--skip-collection of the whole time series exits 0") or diag($output);
unlike(slurp_file($ENV{MONGOSH_LOG}), qr/for \(let i = 0; i < P_COUNT/,
   "the mongosh collection loop is not started");

# --mongodb-only: no system data except the free disk space.
($status, $output, $p) = collect_with("--mongodb-only");
is($status, 0, "--mongodb-only exits 0") or diag($output);
ok(-f "$p-serverstatus", "--mongodb-only collects MongoDB data");
ok(-f "$p-pmap",         "--mongodb-only collects the server's memory map");
ok(-f "$p-disk-space",   "--mongodb-only still checks the free disk space");
is_deeply([ grep { -e "$p-$_" } qw(vmstat iostat ps top df netstat sysctl lsof pidstat_mongod journal) ], [],
   "--mongodb-only collects no system data");

# --system-only with a trigger that does not use MongoDB: no mongosh at all.
unlink $ENV{MONGOSH_ARGS_LOG};
($status, $output, $p) = collect_with("--system-only", "--function", "cpu");
is($status, 0, "--system-only exits 0") or diag($output);
ok(!-e $ENV{MONGOSH_ARGS_LOG}, "--system-only --function cpu does not run mongosh");
ok(-f "$p-vmstat", "--system-only collects system data");
is_deeply([ grep { -e "$p-$_" } qw(serverstatus currentop hostinfo mongostat mongotop pmap) ], [],
   "--system-only collects no MongoDB data");

# --system-only with a trigger that uses MongoDB still connects to it.
unlink $ENV{MONGOSH_ARGS_LOG};
($status, $output, $p) = collect_with("--system-only");
ok(-e $ENV{MONGOSH_ARGS_LOG}, "--system-only --function status runs mongosh");

($status, $output) = collect_with("--system-only", "--mongodb-only");
like($output, qr/Both options --system-only and --mongodb-only specified/,
   "--system-only with --mongodb-only is reported");

# --collect-gdb, --collect-strace and --collect-tcpdump, for the PID and port
# the server reports (4242 and 27018 in the fake mongosh).
($status, $output, $p) = collect_with("--collect-gdb", "--collect-strace", "--collect-tcpdump");
is($status, 0, "--collect-gdb/strace/tcpdump exit 0") or diag($output);
like(slurp_file("$p-stacktrace"), qr/^gdb -ex set pagination 0 -ex thread apply all bt --batch -p 4242$/m,
   "--collect-gdb prints all stack traces of the server");
is(slurp_file("$p-strace"), "strace started\nstrace stopped\n", "--collect-strace is stopped at the end");
like(slurp_file("$p-tcpdump"), qr/^tcpdump -i any -s 4096 -w \S+ port 27018$/m,
   "--collect-tcpdump captures the server's port");
# The real ps: the fake one in PATH lists fixed processes.
my $running = `/bin/ps -ax -o command 2>/dev/null`;
unlike($running, qr/\Q$fakebin\E\/(?:strace|tcpdump)/, "strace and tcpdump are not left running");

# --notify-by-email
($status, $output) = collect_with("--notify-by-email", 'dba@example.com');
like(slurp_file($ENV{MAIL_LOG}), qr/^mail -s Collect triggered on \S+ dba\@example\.com\nNot stalking; collect triggered immediately on /m,
   "--notify-by-email sends an email");
like($output, qr/--notify-by-email=dba\@example\.com/, "--notify-by-email is in the options logged");

done_testing;
