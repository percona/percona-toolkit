#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;
use English qw(-no_match_vars);
use Test::More;
use Time::HiRes qw(sleep);

use PerconaTest;
use DSNParser;
use Sandbox;
require VersionParser;

my $dp = new DSNParser(opts => $dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('replica1');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}

my $cnf      = '/tmp/12346/my.sandbox.cnf';
my $pid_file = "/tmp/pt-stalk.collections.pid.$PID";
my $log_file = "/tmp/pt-stalk.collections.log.$PID";
my $dest     = "/tmp/pt-stalk.collections.$PID";
my $retval;

sub cleanup {
   diag(`rm $pid_file $log_file 2>/dev/null`);
   diag(`rm -rf $dest 2>/dev/null`);
}

sub start_locking_thread_1 {
   my ($dsn_opts_local) = @_;
   my $dp_local = new DSNParser(opts => $dsn_opts_local);
   my $sb_local = new Sandbox(basedir => '/tmp', DSNParser => $dp_local);
   $sb_local->load_file('replica1', 't/pt-stalk/samples/PT-1897-1.sql');
}

sub start_locking_thread_2 {
   my ($dsn_opts_local) = @_;
   my $dp_local = new DSNParser(opts => $dsn_opts_local);
   my $sb_local = new Sandbox(basedir => '/tmp', DSNParser => $dp_local);
   $sb_local->load_file('replica1', 't/pt-stalk/samples/PT-1897-2.sql');
}

sub start_ps_thread {
   my ($dsn_opts_local) = @_;
   my $dp_local = new DSNParser(opts => $dsn_opts_local);
   my $sb_local = new Sandbox(basedir => '/tmp', DSNParser => $dp_local);
   $sb_local->load_file('replica1', 't/pt-stalk/samples/ps.sql');
}

sub assert_collected_nonempty {
   my ( $pattern, $label ) = @_;
   my ($file) = grep { -f $_ } glob($pattern);

   ok(
      $file,
      "Collects $label"
   ) or diag(`ls -l $dest 2>/dev/null`, `cat $log_file 2>/dev/null`);

   ok(
      $file && -s $file,
      "$label has data"
   ) or diag($file ? `cat $file 2>/dev/null` : `ls -l $dest 2>/dev/null`);

   return $file;
}

cleanup();

if ( $sandbox_version ge '5.7' ) {
   $dbh->do("UPDATE performance_schema.setup_instruments SET enabled='YES', timed='YES' WHERE NAME IN ('transaction')");
}

my $thr1 = threads->create('start_locking_thread_1', $dsn_opts);
$thr1->detach();
threads->yield();
sleep 1;

my $thr2 = threads->create('start_locking_thread_2', $dsn_opts);
$thr2->detach();
threads->yield();

my $thr3 = threads->create('start_ps_thread', $dsn_opts);
$thr3->detach();
threads->yield();

$retval = system("$trunk/bin/pt-stalk --no-stalk --pid $pid_file --log $log_file --dest $dest --run-time 5 --iterations 1 -- --defaults-file=$cnf >$log_file 2>&1");

sleep 10;
PerconaTest::kill_program(pid_file => $pid_file);

is(
   $retval >> 8,
   0,
   'pt-stalk exits 0'
);

ok(
   -d $dest,
   'Creates collect destination'
);

my $lock_waits_file = assert_collected_nonempty("$dest/*-lock-waits", '*-lock-waits');
my $transactions_file = assert_collected_nonempty("$dest/*-transactions", '*-transactions');
my $innodb_status_file = assert_collected_nonempty("$dest/*-innodbstatus[12]", '*-innodbstatus[12]');
my $ps_locks_file = assert_collected_nonempty("$dest/*-ps-locks-transactions", '*-ps-locks-transactions');
my $prepared_stmt_file = assert_collected_nonempty("$dest/*-prepared-statements", '*-prepared-statements');
my $replica_status_file = assert_collected_nonempty("$dest/*-${replica_name}-status", "*-${replica_name}-status");

like(
   slurp_file($lock_waits_file),
   qr/waiting_trx_id|who_blocks/,
   'lock_waits content captured'
);

like(
   slurp_file($transactions_file),
   qr/INNODB_TRX|data_locks/i,
   'transactions content captured'
);

like(
   slurp_file($innodb_status_file),
   qr/INNODB/i,
   'innodb_status content captured'
);

like(
   slurp_file($ps_locks_file),
   qr/performance_schema\.(metadata_locks|table_handles|events_transactions)/,
   'ps_locks_transactions content captured'
);

like(
   slurp_file($prepared_stmt_file),
   qr/TS\s+\d+/,
   'ps_prepared_statements content captured'
);

like(
   slurp_file($replica_status_file),
   qr/SHOW\s+(REPLICA|SLAVE)\s+STATUS/i,
   'replica_status content captured'
);

SKIP: {
   skip 'These tests require TokuDB', 2 if ( !$sb->has_engine('source', 'TOKUDB') );

   my ($tokudb_file) = glob("$dest/*-tokudbstatus*");
   ok($tokudb_file, 'Collects *-tokudbstatus*') or diag(`ls -l $dest 2>/dev/null`);
   ok($tokudb_file && -s $tokudb_file, '*-tokudbstatus* has data');
}

SKIP: {
   skip 'These tests require MyRocks', 2 if ( !$sb->has_engine('source', 'ROCKSDB') );

   my ($rocksdb_file) = glob("$dest/*-rocksdbstatus*");
   ok($rocksdb_file, 'Collects *-rocksdbstatus*') or diag(`ls -l $dest 2>/dev/null`);
   ok($rocksdb_file && -s $rocksdb_file, '*-rocksdbstatus* has data');
}

cleanup();
if ( $sandbox_version eq '5.7' ) {
   $dbh->do("UPDATE performance_schema.setup_instruments SET enabled='NO', timed='NO' WHERE NAME IN ('transaction')");
}

$sb->wipe_clean($dbh);
ok($sb->ok(), 'Sandbox servers') or BAIL_OUT(__FILE__ . ' broke the sandbox');
done_testing;
