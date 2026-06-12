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

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempdir tempfile /;

our $delay = 10;

my $tmp_file = File::Temp->new();
my $tmp_file_name = $tmp_file->filename;
unlink $tmp_file_name;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
if ($sb->is_cluster_mode) {
    plan skip_all => 'Not for PXC';
}

# We need third replica to redirect pt-osc in case of one or standard disconnects
diag(`$trunk/sandbox/start-sandbox replica 12348 12345`);

my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh1 = $sb->get_dbh_for('replica1');
my $replica_dbh2 = $sb->get_dbh_for('replica2');
my $replica_dbh3 = $sb->get_dbh_for('source1');
my $source_dsn = 'h=127.0.0.1,P=12345,u=msandbox,p=msandbox';
my $replica_dsn1 = 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox';
my $replica_dsn2 = 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox';
my $sample = "t/pt-online-schema-change/samples";

# We need sync_relay_log=1 to keep changes after replica restart
my $cnf = '/tmp/12347/my.sandbox.cnf';
diag(`cp $cnf $cnf.bak`);
diag(`echo "[mysqld]" > /tmp/12347/my.sandbox.2.cnf`);
diag(`echo "sync_relay_log=1" >> /tmp/12347/my.sandbox.2.cnf`);
diag(`echo "sync_relay_log_info=1" >> /tmp/12347/my.sandbox.2.cnf`);
diag(`echo "relay_log_recovery=1" >> /tmp/12347/my.sandbox.2.cnf`);
diag(`echo "!include /tmp/12347/my.sandbox.2.cnf" >> $cnf`);
diag(`/tmp/12347/stop >/dev/null`);
sleep 1;
diag(`/tmp/12347/start >/dev/null`);

# DSN table for further tests
$sb->load_file('source', "$sample/create_dsns.sql");

sub reset_query_cache {
    my @dbhs = @_;
    return if ($sandbox_version ge '8.0');
    foreach my $dbh (@dbhs) {
        $dbh->do('RESET QUERY CACHE');
    }
}

# 1) Set the replica delay to 0 just in case we are re-running the tests without restarting the sandbox.
# 2) Load sample data
# 3) Set the replica delay to 30 seconds to be able to see the 'waiting' message.
diag("Setting replica delay to 0 seconds");
$sb->wait_for_replicas(replica => 'source1');
$replica_dbh1->do("STOP ${replica_name}");
$replica_dbh3->do("STOP ${replica_name}");
$source_dbh->do("RESET ${source_reset}");
$replica_dbh1->do("RESET ${replica_name}");
$replica_dbh1->do("START ${replica_name}");
$replica_dbh3->do("RESET ${replica_name}");
$replica_dbh3->do("START ${replica_name}");

diag('Loading test data');
$sb->load_file('source', "t/pt-online-schema-change/samples/replica_lag.sql");

# Should be greater than chunk-size and big enough, so pt-osc will wait for delay
my $num_rows = 5000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt178 $num_rows`);

$sb->wait_for_replicas();
$sb->wait_for_replicas(replica => 'source1');

# Plan for tests
# 1. Basic test: start tool on some huge table, stop replica, wait few seconds, start replica. Check if tool restarted with option and failed with error without. 
# 2. Delayed replicas
# 3. Places to test:
#  - get_dbh
#  - SELECT @@SERVER_ID
# 4. Replica never returns
#  - die after timeout
#  - inject new replica
#  - ignore after timeout


diag("Setting replica delay to $delay seconds");

$replica_dbh1->do("STOP ${replica_name}");
$replica_dbh1->do("CHANGE ${source_change} TO ${source_name}_DELAY=$delay");
$replica_dbh1->do("START ${replica_name}");

# Run a full table scan query to ensure the replica is behind the source
# There is no query cache in MySQL 8.0+
reset_query_cache($source_dbh, $source_dbh);
# Update one row so replica is delayed
$source_dbh->do('UPDATE `test`.`pt178` SET f2 = f2 + 1 LIMIT 1');
$source_dbh->do('UPDATE `test`.`pt178` SET f2 = f2 + 1 WHERE f1 = ""');

diag("Starting tests...");

my $max_lag = $delay / 2;
# We need to sleep, otherwise pt-osc can finish before replica is delayed
sleep($max_lag);

my $args = "$source_dsn,D=test,t=pt178 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --nofail-on-stopped-replication";

   my ($fh, $filename) = tempfile();
   my $pid = fork();

   if (!$pid) {
      open(STDERR, '>', $filename);
      open(STDOUT, '>', $filename);
      exec("$trunk/bin/pt-online-schema-change $args");
   }

   sleep($max_lag + $max_lag/2);
   # restart replica 12347
   diag(`/tmp/12347/stop >/dev/null`);
   sleep 1;
   $source_dbh->do("UPDATE test_recursion_method.dsns SET dsn='D=test_recursion_method,t=dsns,P=12348,h=127.0.0.1,u=root,p=msandbox' WHERE id=2");

   waitpid($pid, 0);
   my $output = do {
      local $/ = undef;
      <$fh>;
   };

like(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   "pt-osc completes successfully when one of replicas is stopped, option --nofail-on-stopped-replication is specified, and another replica was specified in the dsns table as a replacement",
) or diag($output);

diag(`/tmp/12347/start >/dev/null`);
# #############################################################################
# Done.
# #############################################################################
diag("Cleaning");
diag(`$trunk/sandbox/stop-sandbox 12348`);
$replica_dbh2 = $sb->get_dbh_for('replica2');
diag("Setting replica delay to 0 seconds");
$replica_dbh1->do("STOP ${replica_name}");
$replica_dbh2->do("STOP ${replica_name}");
$source_dbh->do("RESET ${source_reset}");
$replica_dbh1->do("RESET ${replica_name}");
$replica_dbh2->do("RESET ${replica_name}");
$replica_dbh1->do("START ${replica_name}");
$replica_dbh2->do("START ${replica_name}");
#$replica_dbh2->do("uninstall plugin simple_rewrite_plugin");

diag(`mv $cnf.bak $cnf`);

diag(`/tmp/12347/stop >/dev/null`);
diag(`/tmp/12347/start >/dev/null`);

diag("Dropping test databases");
$source_dbh->do("DROP DATABASE test_recursion_method");
$source_dbh->do("DROP DATABASE IF EXISTS test");
$sb->wait_for_replicas();

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

diag(`/tmp/12345/stop >/dev/null`);
diag(`/tmp/12345/start >/dev/null`);

done_testing;
