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

my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh1 = $sb->get_dbh_for('replica1');
my $replica_dbh2 = $sb->get_dbh_for('replica2');
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
$replica_dbh1->do("STOP ${replica_name}");
$source_dbh->do("RESET ${source_reset}");
$replica_dbh1->do("RESET ${replica_name}");
$replica_dbh1->do("START ${replica_name}");

diag('Loading test data');
$sb->load_file('source', "t/pt-online-schema-change/samples/replica_lag.sql");

# Should be greater than chunk-size and big enough, so pt-osc will wait for delay
my $num_rows = 5000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt178 $num_rows`);

# DSN table for further tests
$sb->load_file('source', "$sample/create_dsns.sql");

$sb->wait_for_replicas();

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

# This is the base test, just to ensure that without using --check-replica-lag nor --skip-check-replica-lag
# pt-online-schema-change will wait on the replica at port 12346

my $max_lag = $delay / 2;
# We need to sleep, otherwise pt-osc can finish before replica is delayed
sleep($max_lag);

# Basic test: we check if pt-osc fails if replica restarted while it is running with default options

sub base_test {
   my ($args) = @_;

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
   diag(`/tmp/12347/start >/dev/null`);

   waitpid($pid, 0);
   my $output = do {
      local $/ = undef;
      <$fh>;
   };

   unlink $filename;

   return $output;
}

sub crash_test {
   my ($args) = @_;

   my ($fh, $filename) = tempfile();
   my $pid = fork();

   if (!$pid) {
       open(STDERR, '>', $filename);
      open(STDOUT, '>', $filename);
      exec("$trunk/bin/pt-online-schema-change $args");
   }

   sleep($max_lag + 10);
   # restart replica 12347
   diag(`/tmp/12347/start >/dev/null`);

   waitpid($pid, 0);
   my $output = do {
      local $/ = undef;
      <$fh>;
   };

   unlink $filename;

   return $output;
}

sub error_test {
   my ($test, $pattern, $query) = @_;

   $replica_dbh2->do("SET GLOBAL simple_rewrite_plugin_action='rewrite'");
   $replica_dbh2->do("SET GLOBAL simple_rewrite_plugin_pattern='$pattern'");
   $replica_dbh2->do("SET GLOBAL simple_rewrite_plugin_query='$query'");

   my $args = "$source_dsn,D=test,t=pt178,A=utf8 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5";

   my $output = `$trunk/bin/pt-online-schema-change $args 2>&1`;

   unlike(
      $output,
      qr/Successfully altered `test`.`pt178`/s,
      "pt-osc fails with error if replica returns error when $test",
   );

   $args = "$source_dsn,D=test,t=pt178,A=utf8 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --nofail-on-stopped-replication";

   $output = `$trunk/bin/pt-online-schema-change $args 2>&1`;

   unlike(
      $output,
      qr/Successfully altered `test`.`pt178`/s,
      "pt-osc fails with error if replica returns error when $test and option --nofail-on-stopped-replication is specified",
   );

   $replica_dbh2->do("SET GLOBAL simple_rewrite_plugin_pattern=''");
   $replica_dbh2 = $sb->get_dbh_for('replica2');
   $replica_dbh2->do("SET GLOBAL simple_rewrite_plugin_pattern='$pattern'");
   $replica_dbh2->do("SET GLOBAL simple_rewrite_plugin_action='abort'");

   $args = "$source_dsn,D=test,t=pt178,A=utf8 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5";

   $output = crash_test($args);

   unlike(
      $output,
      qr/Successfully altered `test`.`pt178`/s,
      "pt-osc fails with error if replica disconnects when $test",
   );

   $replica_dbh2 = $sb->get_dbh_for('replica2');
   $replica_dbh2->do("SET GLOBAL simple_rewrite_plugin_pattern='$pattern'");
   $replica_dbh2->do("SET GLOBAL simple_rewrite_plugin_action='abort'");

   $args = "$source_dsn,D=test,t=pt178,A=utf8 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --nofail-on-stopped-replication";

   $output = crash_test($args);

   like(
      $output,
      qr/Successfully altered `test`.`pt178`/s,
      "pt-osc finishes succesfully if replica disconnects when $test and option --nofail-on-stopped-replication is specified",
   );

   $replica_dbh2 = $sb->get_dbh_for('replica2');
   $replica_dbh2->do("SET GLOBAL simple_rewrite_plugin_action='rewrite'");
}

diag("Starting base tests. This is going to take some time due to the delay in the replica");

my $output = base_test("$source_dsn,D=test,t=pt178 --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5");

unlike(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   "pt-osc fails when one of replicas is restarted",
);

# pt-osc doesn't fail if replica is restarted and option --nofail-on-stopped-replication specified
$output = base_test("$source_dsn,D=test,t=pt178 --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --nofail-on-stopped-replication");

like(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   "pt-osc completes successfully when one of replicas is restarted and option --nofail-on-stopped-replication is specified",
);

$output = base_test("$source_dsn,D=test,t=pt178 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5");

unlike(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   "pt-osc fails with recursion-method=dsn when one of replicas is restarted",
);

$output = base_test("$source_dsn,D=test,t=pt178 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --nofail-on-stopped-replication");

like(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   "pt-osc completes successfully with recursion-method=dsn when one of replicas is restarted and option --nofail-on-stopped-replication is specified",
);

# Errors that happen while pt-osc executes SQL while checking replica availability.
# We check few scenarios.
# - Error not related to connection: pt-osc aborted regardless option --nofail-on-stopped-replication
# - Error, related to connection: pt-osc behavior depends on option --nofail-on-stopped-replication
# We work only with replica with port 12347 here.
diag("Starting replica lost and error tests");

SKIP: {
   $replica_dbh2 = $sb->get_dbh_for('replica2');
   eval { $replica_dbh2->do("install plugin simple_rewrite_plugin soname 'simple_rewrite_plugin.so'") };
   if ( $EVAL_ERROR && $EVAL_ERROR !~ m/Function 'simple_rewrite_plugin' already exists/) {
      skip 'These tests require simple_rewrite_plugin. You can get it from https://github.com/svetasmirnova/simple_rewrite_plugin';
   }

   my @res = $replica_dbh2->selectrow_array("select count(*) from information_schema.plugins where plugin_name='simple_rewrite_plugin' and PLUGIN_STATUS='ACTIVE'");
   if ( $res[0] != 1 ) {
      skip 'These tests require simple_rewrite_plugin in active status';
   }

   # get_dbh sets character set connection
   $source_dbh->do("UPDATE test_recursion_method.dsns SET dsn='D=test_recursion_method,t=dsns,P=12346,h=127.0.0.1,u=root,p=msandbox,A=utf8' WHERE id=1");
   $source_dbh->do("UPDATE test_recursion_method.dsns SET dsn='D=test_recursion_method,t=dsns,P=12347,h=127.0.0.1,u=root,p=msandbox,A=utf8' WHERE id=2");

   error_test("setting character set", '.*(SET NAMES) "?([[:alnum:]]+)"?.*', '$1 $2$2');

   $source_dbh->do("UPDATE test_recursion_method.dsns SET dsn='D=test_recursion_method,t=dsns,P=12346,h=127.0.0.1,u=root,p=msandbox' WHERE id=1");
   $source_dbh->do("UPDATE test_recursion_method.dsns SET dsn='D=test_recursion_method,t=dsns,P=12347,h=127.0.0.1,u=root,p=msandbox' WHERE id=2");

   # get_dbh selects SQL mode
   error_test("selecting SQL mode", 'SELECT @@SQL_MODE', 'SELEC @@SQL_MODE');

   # get_dbh sets SQL mode
   error_test("setting SQL_QUOTE_SHOW_CREATE", 'SET @@SQL_QUOTE_SHOW_CREATE.*', 'SE @@SQL_QUOTE_SHOW_CREATE = 1');

   # get_dbh selects version
   error_test("selecting MySQL version", 'SELECT VERSION.*', 'SELEC VERSION()');

   # get_dbh queries server character set
   error_test("querying server character set", "SHOW VARIABLES LIKE \\'character_set_server\\'", "SHO VARIABLES LIKE \\'character_set_server\\'");

   # get_dbh sets character set utf8mb4 in version 8+
   if ($sandbox_version ge '8.0') {
      error_test("setting character set utf8mb4", "SET NAMES \\'utf8mb4\\'", "SET NAMES \\'utf8mb4utf8mb4\\'");
   }

   # recurse_to_replicas asks for SERVER_ID
   error_test("selecting server id", 'SELECT @@SERVER_ID.*', 'SELEC @@SERVER_ID');

   $replica_dbh2 = $sb->get_dbh_for('replica2');
   $replica_dbh2->do("uninstall plugin simple_rewrite_plugin");
}

# #############################################################################
# Done.
# #############################################################################
diag("Cleaning");
$replica_dbh2 = $sb->get_dbh_for('replica2');
diag("Setting replica delay to 0 seconds");
$replica_dbh1->do("STOP ${replica_name}");
$replica_dbh2->do("STOP ${replica_name}");
$source_dbh->do("RESET ${source_reset}");
$replica_dbh1->do("RESET ${replica_name}");
$replica_dbh2->do("RESET ${replica_name}");
$replica_dbh1->do("START ${replica_name}");
$replica_dbh2->do("START ${replica_name}");

diag(`mv $cnf.bak $cnf`);

diag(`/tmp/12347/stop >/dev/null`);
diag(`/tmp/12347/start >/dev/null`);

diag("Dropping test database");
$source_dbh->do("DROP DATABASE IF EXISTS test");
$sb->wait_for_replicas();

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
