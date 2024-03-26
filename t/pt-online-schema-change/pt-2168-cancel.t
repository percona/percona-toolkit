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

# We need third slave to redirect pt-osc in case of one or standard disconnects
diag(`$trunk/sandbox/start-sandbox slave 12348 12345`);

my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh1 = $sb->get_dbh_for('slave1');
my $slave_dbh2 = $sb->get_dbh_for('slave2');
my $slave_dbh3 = $sb->get_dbh_for('master1');
my $master_dsn = 'h=127.0.0.1,P=12345,u=msandbox,p=msandbox';
my $slave_dsn1 = 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox';
my $slave_dsn2 = 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox';
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
$sb->load_file('master', "$sample/create_dsns.sql");

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
$sb->wait_for_slaves(slave => 'master1');
$slave_dbh1->do('STOP SLAVE');
$slave_dbh3->do('STOP SLAVE');
$master_dbh->do("RESET MASTER");
$slave_dbh1->do('RESET SLAVE');
$slave_dbh1->do('START SLAVE');
$slave_dbh3->do('RESET SLAVE');
$slave_dbh3->do('START SLAVE');

diag('Loading test data');
$sb->load_file('master', "t/pt-online-schema-change/samples/slave_lag.sql");

# Should be greater than chunk-size and big enough, so pt-osc will wait for delay
my $num_rows = 5000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt178 $num_rows`);

$sb->wait_for_slaves();
$sb->wait_for_slaves(slave => 'master1');

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

diag("Starting tests...");

my $max_lag = $delay / 2;
# We need to sleep, otherwise pt-osc can finish before slave is delayed
sleep($max_lag);

my $args = "$master_dsn,D=test,t=pt178 --recursion-method=dsn=D=test_recursion_method,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --nofail-on-stopped-replication";

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
   $master_dbh->do("UPDATE test_recursion_method.dsns SET dsn='D=test_recursion_method,t=dsns,P=12348,h=127.0.0.1,u=root,p=msandbox' WHERE id=2");

   waitpid($pid, 0);
   my $output = do {
      local $/ = undef;
      <$fh>;
   };

like(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   "pt-osc completes successfully when one of replicas is stopped, option --nofail-on-stopped-replication is specified, and another replica was specified in the dsns table as a replacement",
);

diag(`/tmp/12347/start >/dev/null`);
# #############################################################################
# Done.
# #############################################################################
diag("Cleaning");
diag(`$trunk/sandbox/stop-sandbox 12348`);
$slave_dbh2 = $sb->get_dbh_for('slave2');
diag("Setting slave delay to 0 seconds");
$slave_dbh1->do('STOP SLAVE');
$slave_dbh2->do('STOP SLAVE');
$master_dbh->do("RESET MASTER");
$slave_dbh1->do('RESET SLAVE');
$slave_dbh2->do('RESET SLAVE');
$slave_dbh1->do('START SLAVE');
$slave_dbh2->do('START SLAVE');
#$slave_dbh2->do("uninstall plugin simple_rewrite_plugin");

diag(`mv $cnf.bak $cnf`);

diag(`/tmp/12347/stop >/dev/null`);
diag(`/tmp/12347/start >/dev/null`);

diag("Dropping test database");
$master_dbh->do("DROP DATABASE IF EXISTS test");
$sb->wait_for_slaves();

$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
