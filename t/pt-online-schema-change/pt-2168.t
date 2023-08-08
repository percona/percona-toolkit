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

our $delay = 30;

my $tmp_file = File::Temp->new();
my $tmp_file_name = $tmp_file->filename;
unlink $tmp_file_name;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
if ($sb->is_cluster_mode) {
    plan skip_all => 'Not for PXC';
} else {
    plan tests => 3;
}                                  
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh = $sb->get_dbh_for('slave1');
my $master_dsn = 'h=127.0.0.1,P=12345,u=msandbox,p=msandbox';
my $slave_dsn = 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox';

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
$slave_dbh->do('STOP SLAVE');
$master_dbh->do("RESET MASTER");
$slave_dbh->do('RESET SLAVE');
$slave_dbh->do('START SLAVE');

diag('Loading test data');
$sb->load_file('master', "t/pt-online-schema-change/samples/slave_lag.sql");

# Should be greater than chunk-size and big enough, so pt-osc will wait for delay
my $num_rows = 5000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt178 $num_rows`);

$sb->wait_for_slaves();

# Plan for tests
# 1. Basic test: start tool on some huge table, stop slave, wait few seconds, start slave. Check if tool restarted with option and failed with error without. 
# 2. Delayed slaves
# 3. Places to test:
#  - get_dbh
#  - SELECT @@SERVER_ID


diag("Setting slave delay to $delay seconds");

$slave_dbh->do('STOP SLAVE');
$slave_dbh->do("CHANGE MASTER TO MASTER_DELAY=$delay");
$slave_dbh->do('START SLAVE');

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

my $args = "$master_dsn,D=test,t=pt178 --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5";
diag("Starting base test. This is going to take some time due to the delay in the slave");
diag("pid: $tmp_file_name");

my ($fh, $filename) = tempfile();
my $pid = fork();

if (!$pid) {
    open(STDERR, '>', $filename);
    open(STDOUT, '>', $filename);
    exec("$trunk/bin/pt-online-schema-change $args");
}

sleep($max_lag + 10);
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

unlike(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   "pt-osc fails when one of replicas is restarted",
);

$args = "$master_dsn,D=test,t=pt178 --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --wait-lost-replicas";
diag("Starting test with option --wait-lost-replicas. This is going to take some time due to the delay in the slave");
diag("pid: $tmp_file_name");

($fh, $filename) = tempfile();
$pid = fork();

if (!$pid) {
    open(STDERR, '>', $filename);
    open(STDOUT, '>', $filename);
    exec("$trunk/bin/pt-online-schema-change $args");
}

sleep($max_lag + 10);
# restart slave 12347
diag(`/tmp/12347/stop >/dev/null`);
sleep 1;
diag(`/tmp/12347/start >/dev/null`);

waitpid($pid, 0);
$output = do {
      local $/ = undef;
      <$fh>;
};

unlink $filename;

like(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   "pt-osc completes successfully when one of replicas is restarted and option --wait-lost-replicas is specified",
);

#diag($output);

#my $args = "$master_dsn,D=test,t=pt178 --execute --chunk-size 10 --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --wait-lost-replicas";

diag("Setting slave delay to 0 seconds");
$slave_dbh->do('STOP SLAVE');
$master_dbh->do("RESET MASTER");
$slave_dbh->do('RESET SLAVE');
$slave_dbh->do('START SLAVE');

$master_dbh->do("DROP DATABASE IF EXISTS test");
$sb->wait_for_slaves();

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
