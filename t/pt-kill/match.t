#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 16;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-kill";
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $slave_dbh = $sb->get_dbh_for('slave1');

my @args = qw(--test-matching);
my $output;

# #############################################################################
# Test match commands.
# #############################################################################
$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset001.txt", qw(--match-info show --print)); }
);
like(
   $output,
   qr/KILL 9 \(Query 0 sec\) show processlist/,
   '--match-info'
);

$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset002.txt", qw(--match-command Query --print)); }
);
is(
   $output,
   '',
   'Ignore State=Locked by default'
);

$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset002.txt", qw(--match-command Query --ignore-state), "''", "--print"); }
);
like(
   $output,
   qr/KILL 2 \(Query 5 sec\) select \* from foo2/,
   "Can override default ignore State=Locked with --ignore-state ''"
);

$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset003.txt", "--match-state", "Sorting result", "--print"); }
);
like(
   $output,
   qr/KILL 29393378 \(Query 3 sec\)/,
   '--match-state'
);

$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset003.txt", qw(--match-state Updating --print --victims all)); }
);
like(
   $output,
   qr/(?:(?:KILL 29393612.+KILL 29393640)|(?:KILL 29393640.+KILL 29393612))/s,
   '--victims all'
);

$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset003.txt", qw(--ignore-user remote --match-command Query --print)); }
);
like(
   $output,
   qr/KILL 29393138/,
   '--ignore-user'
);

$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset004.txt", qw(--busy-time 25 --print)); }
);
like(
   $output,
   qr/KILL 54595/,
   '--busy-time'
);

$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset004.txt", qw(--busy-time 30 --print)); }
);
is(
   $output,
   '',
   '--busy-time but no query is busy enough'
);

$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset005.txt", qw(--idle-time 15 --print)); }
);
like(
   $output,
   qr/KILL 29392005 \(Sleep 17 sec\) NULL/,
   '--idle-time'
);

$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset006.txt", qw(--match-state Locked --ignore-state), "''", qw(--busy-time 5 --print)); }
);
like(
   $output,
   qr/KILL 2 \(Query 9 sec\) select \* from foo2/,
   "--match-state Locked --ignore-state '' --busy-time 5"
);

# The queries in recset002 are both State: Locked which is ignored
# by default so nothing should match, not even for --match-all.
$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset002.txt",
      qw(--match-all --print)); }
);
is(
   $output,
   '',
   "--match-all except ignored"
);

# Now --match-all should match.
$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset002.txt",
      qw(--match-all --victims all --print --ignore-state blahblah)); }
);
like(
   $output,
   qr/(?:(?:KILL 1.+KILL 2)|(?:KILL 2.+KILL 1))/s,
   "--match-all"
);

# --query-id option 
$output = output(
   sub { pt_kill::main(@args, "$trunk/t/lib/samples/pl/recset011.txt", qw(--match-all --print --query-id)); }
);
like(
   $output,
   qr/0x69962191E64980E6/,
   '--query-id'
);

# #############################################################################
# Live tests.
# #############################################################################
SKIP: {
   skip "Cannot connect to sandbox slave", 1 unless $slave_dbh;
   
   my $pl        = $slave_dbh->selectall_arrayref('show processlist');
   my @repl_thds = map { $_->[0] } grep { $_->[1] eq 'system user' } @$pl;
   skip "Sandbox slave has no replication threads", unless scalar @repl_thds;

   my $repl_thd_ids = join("|", @repl_thds);

   $output = output(
      sub { pt_kill::main(qw(-F /tmp/12346/my.sandbox.cnf --match-user system --print --run-time 1 --interval 1)); }
   );
   is(
      $output,
      '',
      "Doesn't match replication threads by default"
   );

   $output = output(
      sub { pt_kill::main(qw(-F /tmp/12346/my.sandbox.cnf --match-user system --print --replication-threads --run-time 1 --interval 1)); }
   );
   like(
      $output,
      qr/KILL (?:$repl_thd_ids)/,
      "--replication-threads allows matching replication thread"
   );

   $slave_dbh->disconnect();
};

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
