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
require "$trunk/bin/pt-slave-restart";

if ( $sandbox_version lt '5.6' ) {
   plan skip_all => 'MySQL Version < 5.6, GTID is not available, skipping tests';
}

diag("Stopping/reconfiguring/restarting sandboxes 12345, 12346 and 12347");

diag(`$trunk/sandbox/test-env stop >/dev/null`);
diag(`GTID=1 $trunk/sandbox/test-env start >/dev/null`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh  = $sb->get_dbh_for('master');
my $slave_dbh   = $sb->get_dbh_for('slave1');
my $slave2_dbh  = $sb->get_dbh_for('slave2');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}

$master_dbh->do('DROP DATABASE IF EXISTS test');
$master_dbh->do('CREATE DATABASE test');
$master_dbh->do('CREATE TABLE test.t (a INT)');
$sb->wait_for_slaves;

# Bust replication
$slave_dbh->do('DROP TABLE test.t');
$master_dbh->do('INSERT INTO test.t SELECT 1');
wait_until(
   sub {
      my $row = $slave_dbh->selectrow_hashref('show slave status');
      return $row->{last_sql_errno};
   }
);

my $r = $slave_dbh->selectrow_hashref('show slave status');
like($r->{last_error}, qr/Table 'test.t' doesn't exist'/, 'It is busted');

# Start an instance
diag(`$trunk/bin/pt-slave-restart --max-sleep .25 -h 127.0.0.1 -P 12346 -u msandbox -p msandbox --daemonize --pid /tmp/pt-slave-restart.pid --log /tmp/pt-slave-restart.log`);
my $output = `ps x | grep 'pt-slave-restart \-\-max\-sleep ' | grep -v grep | grep -v pt-slave-restart.t`;
like($output, qr/pt-slave-restart --max/, 'It lives');

unlike($output, qr/Table 'test.t' doesn't exist'/, 'It is not busted');

ok(-f '/tmp/pt-slave-restart.pid', 'PID file created');
ok(-f '/tmp/pt-slave-restart.log', 'Log file created');

my ($pid) = $output =~ /^\s*(\d+)\s+/;
$output = `cat /tmp/pt-slave-restart.pid`;
is($output, $pid, 'PID file has correct PID');

diag(`$trunk/bin/pt-slave-restart --stop -q`);
sleep 1;
$output = `ps -eaf | grep pt-slave-restart | grep -v grep`;
unlike($output, qr/pt-slave-restart --max/, 'It is dead');

diag(`rm -f /tmp/pt-slave-re*`);
ok(! -f '/tmp/pt-slave-restart.pid', 'PID file removed');

# #############################################################################
# Issue 459: mk-slave-restart --error-text is broken
# #############################################################################
# Bust replication again.  At this point, the master has test.t but
# the slave does not.
$master_dbh->do('DROP TABLE IF EXISTS test.t');
$master_dbh->do('CREATE TABLE test.t (a INT)');
sleep 1;
$slave_dbh->do('DROP TABLE test.t');
$master_dbh->do('INSERT INTO test.t SELECT 1');
$output = `/tmp/12346/use -e 'show slave status'`;
like(
   $output,
   qr/Table 'test.t' doesn't exist'/,
   'It is busted again'
);

# Start an instance
$output = `$trunk/bin/pt-slave-restart --max-sleep .25 -h 127.0.0.1 -P 12346 -u msandbox -p msandbox --error-text "doesn't exist" --run-time 1s 2>&1`;
unlike(
   $output,
   qr/Error does not match/,
   '--error-text works (issue 459)'
);


# #############################################################################
# Done.
# #############################################################################
diag(`rm -f /tmp/pt-slave-re*`);
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
diag(`$trunk/sandbox/test-env stop >/dev/null`);
diag(`$trunk/sandbox/test-env start >/dev/null`);

ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
