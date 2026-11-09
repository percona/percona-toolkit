#!/usr/bin/env perl

# --plugin hooks and a trg_plugin trigger, as in pt-stalk.  Uses the fake
# commands; no MongoDB server.

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

my $hooks_log   = "$tmpdir/hooks.log";
my $trg_counter = "$tmpdir/trg-counter";

sub write_file {
   my ($file, $content) = @_;
   open my $fh, ">", $file or die "Cannot write $file: $OS_ERROR";
   print {$fh} $content;
   close $fh;
   return $file;
}

# Every hook appends its name to the log.  before_collect also records the
# prefix of the collection, which plugins can use, as in pt-stalk.
my $plugin = write_file("$tmpdir/plugin.sh", <<"SH");
before_stalk()         { echo "before_stalk" >> "$hooks_log"; }
before_collect()       { echo "before_collect \$prefix" >> "$hooks_log"; }
after_collect()        { echo "after_collect \$1" >> "$hooks_log"; }
after_collect_sleep()  { echo "after_collect_sleep" >> "$hooks_log"; }
after_interval_sleep() { echo "after_interval_sleep" >> "$hooks_log"; }
after_stalk()          { echo "after_stalk" >> "$hooks_log"; }
SH

# The trigger value is 0 on the first two checks and 100 on the third.
my $trigger = write_file("$tmpdir/trigger.sh", <<"SH");
trg_plugin() {
   local n
   n=\$(cat "$trg_counter" 2>/dev/null || echo 0)
   n=\$((n + 1))
   echo "\$n" > "$trg_counter"
   if [ "\$n" -ge 3 ]; then echo 100; else echo 0; fi
}
SH

my $dest = "$tmpdir/collect";
my ($status, $output) = run_capture(
   "bash", $tool,
   "--host", "localhost", "--port", "27017",
   "--function", $trigger,
   "--plugin", $plugin,
   "--threshold", "50",
   "--cycles", "1",
   "--interval", "1",
   "--iterations", "1",
   "--run-time", "1",
   "--sleep", "0",
   "--disk-pct-free", "1",
   "--disk-bytes-free", "1",
   "--verbose", "3",
   "--dest", $dest,
   "--pid", "$tmpdir/pt-mongodb-stalk.pid",
);
is($status, 0, "stalking with a plugin exits 0") or diag($output);

my @hooks = split /\n/, slurp_file($hooks_log);
my ($prefix) = prefixes_in($dest);
my ($collector_pid) = map { m/^after_collect (\d+)$/ ? $1 : () } @hooks;
is_deeply(
   \@hooks,
   [
      "before_stalk",
      "after_interval_sleep",
      "after_interval_sleep",
      "before_collect " . ($prefix || ''),
      "after_collect " . ($collector_pid || ''),
      "after_collect_sleep",
      "after_stalk",
   ],
   "hooks are called in order"
) or diag(join("\n", @hooks));
ok($collector_pid, "after_collect gets the collector's PID");
ok($prefix && -f "$dest/$prefix-trigger", "before_collect gets the collection's prefix");

like($output, qr/Check results: \Q$trigger\E\(connections\.active\)=0, matched=no, cycles_true=0/,
   "trg_plugin values below the threshold do not match");
like($output, qr/Check results: \Q$trigger\E\(connections\.active\)=100, matched=yes, cycles_true=1/,
   "trg_plugin value above the threshold matches");
like($output, qr/Collect 1 triggered/, "trg_plugin triggers the collection");
is(slurp_file($trg_counter), "3\n", "trg_plugin is called once per check");

done_testing;
