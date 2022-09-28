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

if ($ENV{PERCONA_SLOW_BOX}) {
    plan skip_all => 'This test needs a fast machine';
} else {
    #plan tests => 6;
    plan skip_all => 'This test is taking too much time even in fast machines';
}                                  

our $delay = 30;

my $tmp_file = File::Temp->new();
my $tmp_file_name = $tmp_file->filename;
unlink $tmp_file_name;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
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
$slave_dbh->do('RESET SLAVE');
$slave_dbh->do('START SLAVE');

diag('Loading test data');
$sb->load_file('master', "t/pt-online-schema-change/samples/slave_lag.sql");

my $num_rows = 5000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt178 $num_rows`);

diag("Setting slave delay to $delay seconds");

$slave_dbh->do('STOP SLAVE');
$slave_dbh->do("CHANGE MASTER TO MASTER_DELAY=$delay");
$slave_dbh->do('START SLAVE');

# Run a full table scan query to ensure the slave is behind the master
# There is no query cache in MySQL 8.0+
reset_query_cache($master_dbh, $master_dbh);
$master_dbh->do('UPDATE `test`.`pt178` SET f2 = f2 + 1 WHERE f1 = ""');

# This is the base test, ust to ensure that without using --check-slave-lag nor --skip-check-slave-lag
# pt-online-schema-change will wait on the slave at port 12346

my $max_lag = $delay / 2;
my $args = "$master_dsn,D=test,t=pt178 --execute --chunk-size 10 --max-lag $max_lag --alter 'ENGINE=InnoDB' --pid $tmp_file_name";
diag("Starting base test. This is going to take some time due to the delay in the slave");
diag("pid: $tmp_file_name");
my $output = `$trunk/bin/pt-online-schema-change $args 2>&1`;

like(
      $output,
      qr/Replica lag is \d+ seconds on .*  Waiting/s,
      "Base test waits on the correct slave",
);

# Repeat the test now using --check-slave-lag
$args = "$master_dsn,D=test,t=pt178 --execute --chunk-size 1 --max-lag $max_lag --alter 'ENGINE=InnoDB' "
      . "--check-slave-lag h=127.0.0.1,P=12346,u=msandbox,p=msandbox,D=test,t=sbtest --pid $tmp_file_name";

# Run a full table scan query to ensure the slave is behind the master
reset_query_cache($master_dbh, $master_dbh);
$master_dbh->do('UPDATE `test`.`pt178` SET f2 = f2 + 1 WHERE f1 = ""');

diag("Starting --check-slave-lag test. This is going to take some time due to the delay in the slave");
$output = `$trunk/bin/pt-online-schema-change $args 2>&1`;

like(
      $output,
      qr/Replica lag is \d+ seconds on .*  Waiting/s,
      "--check-slave-lag waits on the correct slave",
);

# Repeat the test new adding and removing a slave during the process
$args = "$master_dsn,D=test,t=pt178 --execute --chunk-size 1 --max-lag $max_lag --alter 'ENGINE=InnoDB' "
      . "--recursion-method=dsn=D=test,t=dynamic_replicas --recurse 0 --pid $tmp_file_name";

$master_dbh->do('CREATE TABLE `test`.`dynamic_replicas` (id INTEGER PRIMARY KEY, dsn VARCHAR(255) )');
$master_dbh->do("INSERT INTO `test`.`dynamic_replicas` (id, dsn) VALUES (1, '$slave_dsn')");

# Run a full table scan query to ensure the slave is behind the master
reset_query_cache($master_dbh, $master_dbh);
$master_dbh->do('UPDATE `test`.`pt178` SET f2 = f2 + 1 WHERE f1 = ""');

diag("Starting --recursion-method with changes during the process");
my ($fh, $filename) = tempfile();
my $pid = fork();

if (!$pid) {
    open(STDERR, '>', $filename);
    open(STDOUT, '>', $filename);
    exec("$trunk/bin/pt-online-schema-change $args");
}

sleep(60);
$master_dbh->do("DELETE FROM `test`.`dynamic_replicas` WHERE id = 1;");
waitpid($pid, 0);
$output = do {
      local $/ = undef;
      <$fh>;
};

unlink $filename;

like(
      $output,
      qr/Slave set to watch has changed/s,
      "--recursion-method=dsn updates the slave list",
);

like(
      $output,
      qr/Replica lag is \d+ seconds on .*  Waiting/s,
      "--recursion-method waits on a replica",
);

# Repeat the test now using --skip-check-slave-lag
# Run a full table scan query to ensure the slave is behind the master
reset_query_cache($master_dbh, $master_dbh);
$master_dbh->do('UPDATE `test`.`pt178` SET f2 = f2 + 1 WHERE f1 = ""');

$args = "$master_dsn,D=test,t=pt178 --execute --chunk-size 1 --max-lag $max_lag --alter 'ENGINE=InnoDB' "
      . "--skip-check-slave-lag h=127.0.0.1,P=12346,u=msandbox,p=msandbox,D=test,t=sbtest --pid $tmp_file_name";

diag("Starting --skip-check-slave-lag test. This is going to take some time due to the delay in the slave");
$output = `$trunk/bin/pt-online-schema-change $args 2>&1`;

unlike(
      $output,
      qr/Replica lag is \d+ seconds on .*  Waiting/s,
      "--skip-check-slave-lag is really skipping the slave",
);

diag("Setting slave delay to 0 seconds");
$slave_dbh->do('STOP SLAVE');
$slave_dbh->do('RESET SLAVE');
$slave_dbh->do('START SLAVE');

$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
