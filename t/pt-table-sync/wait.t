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
require "$trunk/bin/pt-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 5;
}

my $output;
my @args = ('--sync-to-master', 'h=127.1,P=12346,u=msandbox,p=msandbox', qw(--print -v));

$sb->load_file('master', 't/pt-table-sync/samples/lag-slave.sql');
wait_until(
   sub {
      my $row;
      eval {
         $row = $slave_dbh->selectrow_hashref("select * from test.t2");
      };
      return 1 if $row && $row->{id};
   },
);

sub lag_slave {
   my $dbh = $sb->get_dbh_for('master');
   for (1..10) {
      $dbh->do("update test.t1 set i=sleep(3) limit 1");
   }
   $dbh->disconnect;
   return;
}

my $pid = fork();
if ( !$pid ) {
   # child
   lag_slave();
   exit;
}

# parent
PerconaTest::wait_until(sub {
   $slave_dbh->selectrow_hashref("show slave status")->{seconds_behind_master}
}) or do {
   kill 15, $pid;
   waitpid ($pid, 0);
   die "Slave did not lag";
};

my $start = time;

$output = output(
   sub { pt_table_sync::main(@args, qw(-t test.t2)) },
);

my $t = time - $start;

like(
   $output,
   qr/Chunk\s+\S+\s+\S+\s+0\s+test\.t2/,
   "Synced table"
);

cmp_ok(
   $t,
   '>',
   1,
   "Sync waited $t seconds for master"
);

# Repeat the test with --wait 0 to test that the sync happens without delay.
PerconaTest::wait_until(sub {
   $slave_dbh->selectrow_hashref("show slave status")->{seconds_behind_master}
}) or do {
   kill 15, $pid;
   waitpid ($pid, 0);
   die "Slave did not lag";
};

$start = time;

$output = output(
   sub { pt_table_sync::main(@args, qw(-t test.t2 --wait 0)) },
);

$t = time - $start;

like(
   $output,
   qr/Chunk\s+\S+\s+\S+\s+0\s+test\.t2/,
   "Synced table"
);

cmp_ok(
   $t,
   '<=',
   1,
   "Sync did not wait for master with --wait 0 ($t seconds)"
);

# #############################################################################
# Done.
# #############################################################################
kill 15, $pid;
waitpid ($pid, 0);
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
