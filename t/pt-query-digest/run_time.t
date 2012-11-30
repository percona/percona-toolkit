#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
use Sandbox;
use Time::HiRes qw(sleep);
require "$trunk/bin/pt-query-digest";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 11;
}

my @args;

# #############################################################################
# Issue 361: Add a --runfor (or something) option to mk-query-digest
# #############################################################################
`$trunk/bin/pt-query-digest --processlist h=127.1,P=12345,u=msandbox,p=msandbox --run-time 3 --port 12345 --log /tmp/mk-query-digest.log --pid /tmp/mk-query-digest.pid --daemonize 1>/dev/null 2>/dev/null`;
chomp(my $pid = `cat /tmp/mk-query-digest.pid`);
sleep 2;
my $output = `ps x | grep $pid | grep processlist | grep -v grep`;
ok(
   $output,
   'Still running for --run-time (issue 361)'
);

sleep 1.5;
$output = `ps x | grep $pid | grep processlist | grep -v grep`;
is(
   $output,
   '',
   'No longer running for --run-time (issue 361)'
);

diag(`rm -rf /tmp/mk-query-digest.log`);

# #############################################################################
# Issue 1150: Make mk-query-digest --run-time behavior more flexible
# #############################################################################
@args = ('--report-format', 'query_report,profile', '--limit', '10');

# --run-time-mode event without a --run-time should result in the same output
# as --run-time-mode clock because the log ts will be effectively ignored.
my $before = output(
   sub { pt_query_digest::main("$trunk/t/lib/samples/slowlogs/slow033.txt",
      '--report-format', 'query_report,profile')
   },
);

@args = ('--report-format', 'query_report,profile', '--limit', '10');

my $after = output(
   sub { pt_query_digest::main(@args, "$trunk/t/lib/samples/slowlogs/slow033.txt",
      qw(--run-time-mode event))
   },
);

is(
   $before,
   $after,
   "Event run time mode doesn't change analysis"
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, "$trunk/t/lib/samples/slowlogs/slow033.txt",
         qw(--run-time-mode event --run-time 1h)) },
      "t/pt-query-digest/samples/slow033-rtm-event-1h.txt"
   ),
   "Run-time mode event 1h"
);

# This is correct because the next event is 1d and 1m after the first.
# So runtime 1d should not include it.
ok(
   no_diff(
      sub { pt_query_digest::main(@args, "$trunk/t/lib/samples/slowlogs/slow033.txt",
         qw(--run-time-mode event --run-time 1d)) },
      "t/pt-query-digest/samples/slow033-rtm-event-1h.txt"
   ),
   "Run-time mode event 1d"
);

# Now we'll get the 2nd event but not the 3rd.
ok(
   no_diff(
      sub { pt_query_digest::main(@args, "$trunk/t/lib/samples/slowlogs/slow033.txt",
         qw(--run-time-mode event --run-time 25h)) },
      "t/pt-query-digest/samples/slow033-rtm-event-25h.txt"
   ),
   "Run-time mode event 25h"
);

# Run-time interval.
push @args, qw(--iterations 0);
ok(
   no_diff(
      sub { pt_query_digest::main(@args, "$trunk/t/lib/samples/slowlogs/slow033.txt",
         qw(--run-time-mode interval --run-time 1d)) },
      "t/pt-query-digest/samples/slow033-rtm-interval-1d.txt"
   ),
   "Run-time mode interval 1d"
);

# This correctly splits these two events:
#   Time: 090727 11:19:30 # User@Host: [SQL_SLAVE] @  []
#   Time: 090727 11:19:31 # User@Host: [SQL_SLAVE] @  []
# The first belongs to the 0-29s interval, the second to the
# 30-60s interval.
ok(
   no_diff(
      sub { pt_query_digest::main(@args, "$trunk/t/lib/samples/slowlogs/slow033.txt",
         qw(--run-time-mode interval --run-time 30)) },
      "t/pt-query-digest/samples/slow033-rtm-interval-30s.txt"
   ),
   "Run-time mode interval 30s"
);

# Now, contrary to the above, those two events are together because they're
# within the same 30m interval.
ok(
   no_diff(
      sub { pt_query_digest::main(@args, "$trunk/t/lib/samples/slowlogs/slow033.txt",
         qw(--run-time-mode interval --run-time 30m)) },
      "t/pt-query-digest/samples/slow033-rtm-interval-30m.txt",
   ),
   "Run-time mode interval 30m"
);

pop @args;  # report --iterations 0
pop @args;
# Like the first 30s run above, but with only 3 interations, only the
# first 3 queries are gotten.
ok(
   no_diff(
      sub { pt_query_digest::main(@args, "$trunk/t/lib/samples/slowlogs/slow033.txt",
         qw(--run-time-mode interval --run-time 30 --iterations 3)) },
      "t/pt-query-digest/samples/slow033-rtm-interval-30s-3iter.txt"
   ),
   "Run-time mode interval and --iterations"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
