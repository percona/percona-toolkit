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
   plan skip_all => "Requires MySQL 5.6";
}

diag(`SAKILA=0 GTID=1 $trunk/sandbox/test-env restart`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');
my $slave2_dbh = $sb->get_dbh_for('slave2');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}

my $slave1_dsn = $sb->dsn_for("slave1");
my $slave2_dsn = $sb->dsn_for("slave2");

my $pid_file = "/tmp/pt-slave-restart-test-$PID.pid";
my $log_file = "/tmp/pt-slave-restart-test-$PID.log";
my $cmd      = "$trunk/bin/pt-slave-restart --daemonize --run-time 5 --max-sleep .25 --pid $pid_file --log $log_file";

sub start {
   my ( $extra ) = @_;
   stop() or return;
   system "$cmd $extra";
   PerconaTest::wait_for_files($pid_file);
}

sub stop() {
   return 1 if !is_running();
   diag(`$trunk/bin/pt-slave-restart --stop -q >/dev/null 2>&1 &`);
   wait_until(sub { !-f $pid_file }, 0.3, 2);
   diag(`rm -f /tmp/pt-slave-restart-sentinel`);
   return is_running() ? 0 : 1;
}

sub is_running {
   chomp(my $running = `ps -eaf | grep -v grep | grep '$cmd'`);
   if (!-f $pid_file && !$running) {
      return 0;
   } elsif (-f $pid_file && !$running) {
      diag(`rm -f $pid_file`);
      return 0;
   }
   return 1;
}

sub wait_repl_broke {
   my $dbh = shift;
   return wait_until(
      sub {
         my $row = $dbh->selectrow_hashref('show slave status');
         return $row->{last_sql_errno};
      }
   );
}

sub wait_repl_ok {
   my $dbh = shift;
   wait_until(
      sub {
         my $row = $dbh->selectrow_hashref('show slave status');
         return $row->{last_sql_errno} == 0;
      },
      0.30,
      5,
   );
}

# #############################################################################
# Basic test to see if restart works with GTID.
# #############################################################################

$master_dbh->do('DROP DATABASE IF EXISTS test');
$master_dbh->do('CREATE DATABASE test');
$master_dbh->do('CREATE TABLE test.t (a INT)');
$sb->wait_for_slaves;

# Bust replication
$slave1_dbh->do('DROP TABLE test.t');
$master_dbh->do('INSERT INTO test.t SELECT 1');
wait_repl_broke($slave1_dbh) or die "Failed to break replication";

my $r = $slave1_dbh->selectrow_hashref('show slave status');
like($r->{last_error}, qr/Table 'test.t' doesn't exist'/, 'slave: Replication broke');

# Start pt-slave-restart and wait up to 5s for it to fix replication
# (it should take < 1s but tests can be really slow sometimes).
start("$slave1_dsn") or die "Failed to start pt-slave-restart";
wait_repl_ok($slave1_dbh);

# Check if replication is fixed.
$r = $slave1_dbh->selectrow_hashref('show slave status');
like(
   $r->{last_errno},
   qr/^0$/,
   'Event is skipped',
) or BAIL_OUT("Replication is broken");

# Stop pt-slave-restart.
stop() or die "Failed to stop pt-slave-restart";

# #############################################################################
# Test the slave of the master.
# #############################################################################

$master_dbh->do('DROP DATABASE IF EXISTS test');
$master_dbh->do('CREATE DATABASE test');
$master_dbh->do('CREATE TABLE test.t (a INT)');
$sb->wait_for_slaves;

# Bust replication
$slave2_dbh->do('DROP TABLE test.t');
$master_dbh->do('INSERT INTO test.t SELECT 1');
wait_repl_broke($slave2_dbh) or die "Failed to break replication";

# fetch the master uuid, which is the machine we need to skip an event from
$r = $master_dbh->selectrow_hashref('select @@GLOBAL.server_uuid as uuid');
my $uuid = $r->{uuid};

$r = $slave2_dbh->selectrow_hashref('show slave status');
like($r->{last_error}, qr/Table 'test.t' doesn't exist'/, 'slaveofslave: Replication broke');

# Start an instance
start("--master-uuid=$uuid $slave2_dsn") or die;
wait_repl_ok($slave2_dbh);

$r = $slave2_dbh->selectrow_hashref('show slave status');
like(
   $r->{last_errno},
   qr/^0$/,
   'Skips event from master on slave2'
) or BAIL_OUT("Replication is broken");

stop() or die "Failed to stop pt-slave-restart";

# #############################################################################
# Test skipping 2 events in a row.
# #############################################################################

$master_dbh->do('DROP DATABASE IF EXISTS test');
$master_dbh->do('CREATE DATABASE test');
$master_dbh->do('CREATE TABLE test.t (a INT)');
$sb->wait_for_slaves;

# Bust replication
$slave2_dbh->do('DROP TABLE test.t');
$master_dbh->do('INSERT INTO test.t SELECT 1');
$master_dbh->do('INSERT INTO test.t SELECT 1');
wait_repl_broke($slave2_dbh) or die "Failed to break replication";

# fetch the master uuid, which is the machine we need to skip an event from
$r = $master_dbh->selectrow_hashref('select @@GLOBAL.server_uuid as uuid');
$uuid = $r->{uuid};

$r = $slave2_dbh->selectrow_hashref('show slave status');
like($r->{last_error}, qr/Table 'test.t' doesn't exist'/, 'slaveofslaveskip2: Replication broke');

# Start an instance
start("--skip-count=2 --master-uuid=$uuid $slave2_dsn") or die;
wait_repl_ok($slave2_dbh);

$r = $slave2_dbh->selectrow_hashref('show slave status');
like(
   $r->{last_errno},
   qr/^0$/,
   'Skips multiple events'
) or BAIL_OUT("Replication is broken");

stop() or die "Failed to stop pt-slave-restart";

# #############################################################################
# Done.
# #############################################################################
diag(`rm -f $pid_file $log_file >/dev/null`);
diag(`$trunk/sandbox/test-env restart`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
