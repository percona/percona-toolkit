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
use Data::Dumper;
use File::Temp qw(tempfile);

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-replica-restart";

if ( $sandbox_version lt '5.6' ) {
   plan skip_all => "Requires MySQL 5.6";
}

diag('Restarting the sandbox');
diag(`SAKILA=0 REPLICATION_THREADS=0 GTID=1 $trunk/sandbox/test-env restart`);
diag("Sandbox restarted");

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica2_dbh = $sb->get_dbh_for('replica2');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
}

my $replica1_dsn = $sb->dsn_for("replica1");
my $replica2_dsn = $sb->dsn_for("replica2");

my $pid_file = "/tmp/pt-replica-restart-test-$PID.pid";
my $log_file = "/tmp/pt-replica-restart-test-$PID.log";
my $cmd      = "$trunk/bin/pt-replica-restart --daemonize --run-time 5 --max-sleep 0.25 --pid $pid_file --log $log_file";

sub start {
   my ( $extra ) = @_;
   stop() or return;
   system "$cmd $extra";
   PerconaTest::wait_for_files($pid_file);
}

sub stop() {
   return 1 if !is_running();
   diag(`$trunk/bin/pt-replica-restart --stop -q >/dev/null 2>&1 &`);
   wait_until(sub { !-f $pid_file }, 0.3, 2);
   diag(`rm -f /tmp/pt-replica-restart-sentinel`);
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
         my $row = $dbh->selectrow_hashref("show ${replica_name} status");
         return $row->{last_sql_errno};
      }
   );
}

sub wait_repl_ok {
   my $dbh = shift;
   wait_until(
      sub {
         my $row = $dbh->selectrow_hashref("show ${replica_name} status");
         return $row->{last_sql_errno} == 0;
      },
      0.30,
      5,
   );
}

# #############################################################################
# Basic test to see if restart works with GTID.
# #############################################################################

$source_dbh->do('DROP DATABASE IF EXISTS test');
$source_dbh->do('CREATE DATABASE test');
$source_dbh->do('CREATE TABLE test.t (a INT)');
$sb->wait_for_replicas;

# Bust replication
$replica1_dbh->do('DROP TABLE test.t');
$source_dbh->do('INSERT INTO test.t SELECT 1');
wait_repl_broke($replica1_dbh) or die "Failed to break replication";

my $r = $replica1_dbh->selectrow_hashref("show ${replica_name} status");
like($r->{last_error}, qr/Table 'test.t' doesn't exist'/, 'replica: Replication broke');

# Start pt-replica-restart and wait up to 5s for it to fix replication
# (it should take < 1s but tests can be really slow sometimes).
start("$replica1_dsn") or die "Failed to start pt-replica-restart";
wait_repl_ok($replica1_dbh);

# Check if replication is fixed.
$r = $replica1_dbh->selectrow_hashref("show ${replica_name} status");
like(
   $r->{last_errno},
   qr/^0$/,
   'Event is skipped',
) or BAIL_OUT("Replication is broken");

# Stop pt-replica-restart.
stop() or die "Failed to stop pt-replica-restart";

# #############################################################################
# Test the replica of the source.
# #############################################################################

$source_dbh->do('DROP DATABASE IF EXISTS test');
$source_dbh->do('CREATE DATABASE test');
$source_dbh->do('CREATE TABLE test.t (a INT)');
$sb->wait_for_replicas;

# Bust replication
$replica2_dbh->do('DROP TABLE test.t');
$source_dbh->do('INSERT INTO test.t SELECT 1');
wait_repl_broke($replica2_dbh) or die "Failed to break replication";

# fetch the source uuid, which is the machine we need to skip an event from
$r = $source_dbh->selectrow_hashref('select @@GLOBAL.server_uuid as uuid');
my $uuid = $r->{uuid};

$r = $replica2_dbh->selectrow_hashref("show ${replica_name} status");
like($r->{last_error}, qr/Table 'test.t' doesn't exist'/, 'replicaofreplica: Replication broke');

# Start an instance
start("--source-uuid=$uuid $replica2_dsn") or die;
wait_repl_ok($replica2_dbh);

$r = $replica2_dbh->selectrow_hashref("show ${replica_name} status");
like(
   $r->{last_errno},
   qr/^0$/,
   'Skips event from source on replica2'
) or BAIL_OUT("Replication is broken");

stop() or die "Failed to stop pt-replica-restart";

# #############################################################################
# Test the replica of the source with deprecated option syntax.
# #############################################################################

$source_dbh->do('DROP DATABASE IF EXISTS test');
$source_dbh->do('CREATE DATABASE test');
$source_dbh->do('CREATE TABLE test.t (a INT)');
$sb->wait_for_replicas;

# Bust replication
$replica2_dbh->do('DROP TABLE test.t');
$source_dbh->do('INSERT INTO test.t SELECT 1');
wait_repl_broke($replica2_dbh) or die "Failed to break replication";

# fetch the source uuid, which is the machine we need to skip an event from
$r = $source_dbh->selectrow_hashref('select @@GLOBAL.server_uuid as uuid');
$uuid = $r->{uuid};

$r = $replica2_dbh->selectrow_hashref("show ${replica_name} status");
like(
   $r->{last_error},
   qr/Table 'test.t' doesn't exist'/,
   'replicaofreplica - deprecated option: Replication broke');

# Start an instance
my (undef, $tempfile) = tempfile();
start("--master-uuid=$uuid $replica2_dsn > $tempfile 2>&1") or die;
wait_repl_ok($replica2_dbh);

like(
   slurp_file($tempfile),
   qr/Option --master-uuid is deprecated and will be removed in future versions./,
   'Deprecation warning printed for legacy option --master-uuid'
);

$r = $replica2_dbh->selectrow_hashref("show ${replica_name} status");
like(
   $r->{last_errno},
   qr/^0$/,
   'Skips event from source on replica2 for deprecated --master-uuid'
) or BAIL_OUT("Replication is broken");

stop() or die "Failed to stop pt-replica-restart";
diag(`rm $tempfile >/dev/null`);

# #############################################################################
# Test skipping 2 events in a row.
# #############################################################################

$source_dbh->do('DROP DATABASE IF EXISTS test');
$source_dbh->do('CREATE DATABASE test');
$source_dbh->do('CREATE TABLE test.t (a INT)');
$sb->wait_for_replicas;

# Bust replication
$replica2_dbh->do('DROP TABLE test.t');
$source_dbh->do('INSERT INTO test.t SELECT 1');
$source_dbh->do('INSERT INTO test.t SELECT 1');
wait_repl_broke($replica2_dbh) or die "Failed to break replication";

# fetch the source uuid, which is the machine we need to skip an event from
$r = $source_dbh->selectrow_hashref('select @@GLOBAL.server_uuid as uuid');
$uuid = $r->{uuid};

$r = $replica2_dbh->selectrow_hashref("show ${replica_name} status");
like($r->{last_error}, qr/Table 'test.t' doesn't exist'/, 'replicaofreplicaskip2: Replication broke');

# Start an instance
start("--skip-count=2 --source-uuid=$uuid $replica2_dsn") or die;
wait_repl_ok($replica2_dbh);

$r = $replica2_dbh->selectrow_hashref("show ${replica_name} status");
like(
   $r->{last_errno},
   qr/^0$/,
   'Skips multiple events'
) or BAIL_OUT("Replication is broken");

stop() or die "Failed to stop pt-replica-restart";

# #############################################################################
# Done.
# #############################################################################
diag(`rm -f $pid_file $log_file >/dev/null`);
diag(`$trunk/sandbox/test-env restart`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
