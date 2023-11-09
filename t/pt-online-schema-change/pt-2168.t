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

my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh1 = $sb->get_dbh_for('slave1');
my $slave_dbh2 = $sb->get_dbh_for('slave2');
my $master_dsn = 'h=127.0.0.1,P=12345,u=msandbox,p=msandbox';
my $slave_dsn1 = 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox';
my $slave_dsn2 = 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox';
my $sample = "t/pt-online-schema-change/samples";

# We need sync_relay_log=1 to have 
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
    return if ($sandbox_version >= '8.0');
    foreach my $dbh (@dbhs) {
        $dbh->do('RESET QUERY CACHE');
    }
}

# 1) Set the slave delay to 0 just in case we are re-running the tests without restarting the sandbox.
# 2) Load sample data
# 3) Set the slave delay to 30 seconds to be able to see the 'waiting' message.
diag("Setting slave delay to 0 seconds");
$slave_dbh1->do('STOP SLAVE');
$master_dbh->do("RESET MASTER");
$slave_dbh1->do('RESET SLAVE');
$slave_dbh1->do('START SLAVE');

diag('Loading test data');
$sb->load_file('master', "t/pt-online-schema-change/samples/slave_lag.sql");

# Should be greater than chunk-size and big enough, so pt-osc will wait for delay
my $num_rows = 5000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt178 $num_rows`);

# DSN table for further tests
$sb->load_file('master', "$sample/create_dsns.sql");

$sb->wait_for_slaves();

# Plan for tests
# 1. Basic test: start tool on some huge table, stop slave, wait few seconds, start slave. Check if tool restarted with option and failed with error without. 
# 2. Delayed slaves
# 3. Places to test:
#  - get_dbh
#  - SELECT @@SERVER_ID
# 4. Slave never returns
#  - die after timeout
#  - inject new slave
#  - ignore after timeout


diag("Setting slave delay to $delay seconds");

$slave_dbh1->do('STOP SLAVE');
$slave_dbh1->do("CHANGE MASTER TO MASTER_DELAY=$delay");
$slave_dbh1->do('START SLAVE');

# Run a full table scan query to ensure the slave is behind the master
# There is no query cache in MySQL 8.0+
reset_query_cache($master_dbh, $master_dbh);
# Update one row so slave is delayed
$master_dbh->do('UPDATE `test`.`pt178` SET f2 = f2 + 1 LIMIT 1');
$master_dbh->do('UPDATE `test`.`pt178` SET f2 = f2 + 1 WHERE f1 = ""');

# This is the base test, just to ensure that without using --check-slave-lag nor --skip-check-slave-lag
# pt-online-schema-change will wait on the slave at port 12346

my $max_lag = $delay / 2;
# We need to sleep, otherwise pt-osc can finish before slave is delayed
sleep($max_lag);

# Basic test: we check if pt-osc fails if replica restarted while it is running with default options

sub base_test {
   my ($args) = @_;
   #diag("pid: $tmp_file_name");

   my ($fh, $filename) = tempfile();
   my $pid = fork();

   if (!$pid) {
      open(STDERR, '>', $filename);
      open(STDOUT, '>', $filename);
      exec("$trunk/bin/pt-online-schema-change $args");
   }

   sleep($max_lag + $max_lag/2);
   # restart slave 12347
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
   #diag("pid: $tmp_file_name");

   my ($fh, $filename) = tempfile();
   my $pid = fork();

   if (!$pid) {
       open(STDERR, '>', $filename);
      open(STDOUT, '>', $filename);
      exec("$trunk/bin/pt-online-schema-change $args");
   }

   sleep($max_lag + 10);
   # restart slave 12347
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

   $slave_dbh2->do("SET GLOBAL simple_rewrite_plugin_action='rewrite'");
   $slave_dbh2->do("SET GLOBAL simple_rewrite_plugin_pattern='$pattern'");
   $slave_dbh2->do("SET GLOBAL simple_rewrite_plugin_query='$query'");

   my $args = "$master_dsn,D=test,t=pt178,A=utf8 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5";

   my $output = `$trunk/bin/pt-online-schema-change $args 2>&1`;

   unlike(
      $output,
      qr/Successfully altered `test`.`pt178`/s,
      "pt-osc fails with error if replica returns error when $test",
   );

   $args = "$master_dsn,D=test,t=pt178,A=utf8 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --nofail-on-stopped-replication";

   $output = `$trunk/bin/pt-online-schema-change $args 2>&1`;

   unlike(
      $output,
      qr/Successfully altered `test`.`pt178`/s,
      "pt-osc fails with error if replica returns error when $test and option --nofail-on-stopped-replication is specified",
   );

   $slave_dbh2->do("SET GLOBAL simple_rewrite_plugin_pattern=''");
   $slave_dbh2 = $sb->get_dbh_for('slave2');
   $slave_dbh2->do("SET GLOBAL simple_rewrite_plugin_pattern='$pattern'");
   $slave_dbh2->do("SET GLOBAL simple_rewrite_plugin_action='abort'");

   $args = "$master_dsn,D=test,t=pt178,A=utf8 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5";

   $output = crash_test($args);

   unlike(
      $output,
      qr/Successfully altered `test`.`pt178`/s,
      "pt-osc fails with error if replica disconnects when $test",
   );

   $slave_dbh2 = $sb->get_dbh_for('slave2');
   $slave_dbh2->do("SET GLOBAL simple_rewrite_plugin_pattern='$pattern'");
   $slave_dbh2->do("SET GLOBAL simple_rewrite_plugin_action='abort'");

   $args = "$master_dsn,D=test,t=pt178,A=utf8 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --nofail-on-stopped-replication";

   $output = crash_test($args);

   like(
      $output,
      qr/Successfully altered `test`.`pt178`/s,
      "pt-osc finishes succesfully if replica disconnects when $test and option --nofail-on-stopped-replication is specified",
   );

   $slave_dbh2 = $sb->get_dbh_for('slave2');
   $slave_dbh2->do("SET GLOBAL simple_rewrite_plugin_action='rewrite'");
}

diag("Starting base tests. This is going to take some time due to the delay in the slave");

my $output = base_test("$master_dsn,D=test,t=pt178 --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5");

unlike(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   "pt-osc fails when one of replicas is restarted",
);

# pt-osc doesn't fail if replica is restarted and option --nofail-on-stopped-replication specified
$output = base_test("$master_dsn,D=test,t=pt178 --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --nofail-on-stopped-replication");

like(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   "pt-osc completes successfully when one of replicas is restarted and option --nofail-on-stopped-replication is specified",
);

$output = base_test("$master_dsn,D=test,t=pt178 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5");

unlike(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   "pt-osc fails with recursion-method=dsn when one of replicas is restarted",
);

$output = base_test("$master_dsn,D=test,t=pt178 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --nofail-on-stopped-replication");

like(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   "pt-osc completes successfully with recursion-method=dsn when one of replicas is restarted and option --nofail-on-stopped-replication is specified",
);

# Errors that happen while pt-osc executes SQL while checking slave availability.
# We check few scenarios.
# - Error not related to connection: pt-osc aborted regardless option --nofail-on-stopped-replication
# - Error, related to connection: pt-osc behavior depends on option --nofail-on-stopped-replication
# We work only with replica with port 12347 here.
diag("Starting replica lost and error tests");

SKIP: {
   $slave_dbh2 = $sb->get_dbh_for('slave2');
   eval { $slave_dbh2->do("install plugin simple_rewrite_plugin soname 'simple_rewrite_plugin.so'") };
   if ( $EVAL_ERROR && $EVAL_ERROR !~ m/Function 'simple_rewrite_plugin' already exists/) {
      skip 'These tests require simple_rewrite_plugin. You can get it from https://github.com/svetasmirnova/simple_rewrite_plugin';
   }

   my @res = $slave_dbh2->selectrow_array("select count(*) from information_schema.plugins where plugin_name='simple_rewrite_plugin' and PLUGIN_STATUS='ACTIVE'");
   if ( $res[0] != 1 ) {
      skip 'These tests require simple_rewrite_plugin in active status';
   }

   # get_dbh sets character set connection
   $master_dbh->do("UPDATE test_recursion_method.dsns SET dsn='D=test_recursion_method,t=dsns,P=12346,h=127.0.0.1,u=root,p=msandbox,A=utf8' WHERE id=1");
   $master_dbh->do("UPDATE test_recursion_method.dsns SET dsn='D=test_recursion_method,t=dsns,P=12347,h=127.0.0.1,u=root,p=msandbox,A=utf8' WHERE id=2");

   error_test("setting character set", '.*(SET NAMES) "?([[:alnum:]]+)"?.*', '$1 $2$2');

   $master_dbh->do("UPDATE test_recursion_method.dsns SET dsn='D=test_recursion_method,t=dsns,P=12346,h=127.0.0.1,u=root,p=msandbox' WHERE id=1");
   $master_dbh->do("UPDATE test_recursion_method.dsns SET dsn='D=test_recursion_method,t=dsns,P=12347,h=127.0.0.1,u=root,p=msandbox' WHERE id=2");

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

   # recurse_to_slaves asks for SERVER_ID
   error_test("selecting server id", 'SELECT @@SERVER_ID.*', 'SELEC @@SERVER_ID');

   $slave_dbh2 = $sb->get_dbh_for('slave2');
   $slave_dbh2->do("uninstall plugin simple_rewrite_plugin");
}

# #############################################################################
# Done.
# #############################################################################
diag("Cleaning");
$slave_dbh2 = $sb->get_dbh_for('slave2');
diag("Setting slave delay to 0 seconds");
$slave_dbh1->do('STOP SLAVE');
$slave_dbh2->do('STOP SLAVE');
$master_dbh->do("RESET MASTER");
$slave_dbh1->do('RESET SLAVE');
$slave_dbh2->do('RESET SLAVE');
$slave_dbh1->do('START SLAVE');
$slave_dbh2->do('START SLAVE');

diag(`mv $cnf.bak $cnf`);

diag(`/tmp/12347/stop >/dev/null`);
diag(`/tmp/12347/start >/dev/null`);

diag("Dropping test database");
$master_dbh->do("DROP DATABASE IF EXISTS test");
$sb->wait_for_slaves();

$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
