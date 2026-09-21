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
my $max_lag = $delay / 2;
my $output;
my $exit;

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
my $sample     = "t/pt-online-schema-change/samples";
my $plugin     = "$trunk/$sample/plugins";

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

sub run_broken_job {
   my ($args) = @_;
   my ($fh, $filename) = tempfile();
   my $pid = fork();

   if (!$pid) {
      open(STDERR, '>', $filename);
      open(STDOUT, '>', $filename);
      exec("$trunk/bin/pt-online-schema-change $args");
   }

   sleep($max_lag + $max_lag/2);
   # stop replica 12347
   diag(`/tmp/12347/stop >/dev/null`);
   sleep 1;

   waitpid($pid, 0);
   my $output = do {
      local $/ = undef;
      <$fh>;
   };

   return $output;
}

sub set_delay {
   $sb->wait_for_replicas();

   diag("Setting replica delay to $delay seconds");
   diag(`/tmp/12345/use -N test -e "DROP TABLE IF EXISTS pt1717_back"`);

   $replica_dbh1->do("STOP ${replica_name}");
   $replica_dbh1->do("CHANGE ${source_change} TO ${source_name}_DELAY=$delay");
   $replica_dbh1->do("START ${replica_name}");

   # Run a full table scan query to ensure the replica is behind the source
   # There is no query cache in MySQL 8.0+
   reset_query_cache($source_dbh, $source_dbh);
   # Update one row so replica is delayed
   $source_dbh->do('UPDATE `test`.`pt1717` SET f2 = f2 + 1 LIMIT 1');
   $source_dbh->do('UPDATE `test`.`pt1717` SET f2 = f2 + 1 WHERE f1 = ""');

   # Creating copy of table pt1717, so we can compare data later
   diag(`/tmp/12345/use -N test -e "CREATE TABLE pt1717_back like pt1717"`);
   diag(`/tmp/12345/use -N test -e "INSERT INTO pt1717_back SELECT * FROM pt1717"`);
}

# 1) Set the replica delay to 0 just in case we are re-running the tests without restarting the sandbox.
# 2) Load sample data
# 3) Set the replica delay to 30 seconds to be able to see the 'waiting' message.
diag("Setting replica delay to 0 seconds");
$replica_dbh1->do("STOP ${replica_name}");
$replica_dbh1->do("CHANGE ${source_change} TO ${source_name}_DELAY=0");
$replica_dbh1->do("START ${replica_name}");

diag('Loading test data');
$sb->load_file('source', "t/pt-online-schema-change/samples/pt-1717.sql");

# Should be greater than chunk-size and big enough, so pt-osc will wait for delay
my $num_rows = 5000;
my $chunk_size = 10;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt1717 $num_rows`);

diag("Starting tests...");

set_delay();

# We need to sleep, otherwise pt-osc can finish before replica is delayed
sleep($max_lag);

my $args = "$source_dsn,D=test,t=pt1717 --execute --chunk-size ${chunk_size} --max-lag $max_lag --alter 'ADD INDEX idx1(f1)' --pid $tmp_file_name --progress time,5 --no-drop-new-table --no-drop-triggers --history";

$output = run_broken_job($args);

like(
   $output,
   qr/`test`.`pt1717` was not altered/s,
   "pt-osc stopped with error as expected",
) or diag($output);

diag(`/tmp/12347/start >/dev/null`);
$sb->wait_for_replicas();

$output = `/tmp/12345/use -N -e "select job_id, upper_boundary from percona.pt_osc_history"`;
my ($job_id, $upper_boundary) = split(/\s+/, $output);

my $copied_rows = `/tmp/12345/use -N -e "select count(*) from test._pt1717_new"`;
chomp($copied_rows);

ok(
   $copied_rows eq $upper_boundary,
   'Upper chunk boundary stored correctly'
) or diag("Copied_rows: ${copied_rows}, upper boundary: ${upper_boundary}");;

($output, $exit) = full_output(
   sub { pt_online_schema_change::main("$source_dsn,D=test,t=pt1717",
         "--execute", "--chunk-size=${chunk_size}", "--max-lag=${max_lag}",
         "--alter=ADD INDEX idx1(f1)",
         "--resume=${job_id}",
         ) }
);

is(
   $exit,
   0,
   'pt-osc works correctly with --resume'
) or diag($exit);

like(
   $output,
   qr/Successfully altered/,
   'Success message printed'
) or diag($output);

# Corrupting job record, so we can test error message
diag(`/tmp/12345/use -N -e "update percona.pt_osc_history set new_table_name=NULL where job_id=${job_id}"`);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main("$source_dsn,D=test,t=pt1717",
         "--execute", "--chunk-size=${chunk_size}", "--max-lag=${max_lag}",
         "--alter=ADD INDEX idx1(f1)",
         "--resume=${job_id}",
         ) }
);

is(
   $exit,
   17,
   'pt-osc works correctly fails with empty boundaries'
) or diag($exit);

like(
   $output,
   qr/Option --resume refers job \d+ with empty boundaries. Exiting./,
   'Correct error message printed'
) or diag($output);

unlike(
   $output,
   qr/Option --resume refers non-existing job ID: \d+. Exiting./,
   'Misleading error message not printed'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
diag("Cleaning");
$replica_dbh2 = $sb->get_dbh_for('replica2');
diag("Setting replica delay to 0 seconds");
$replica_dbh1->do("STOP ${replica_name}");
$replica_dbh2->do("STOP ${replica_name}");
$replica_dbh1->do("CHANGE ${source_change} TO ${source_name}_DELAY=0");
$replica_dbh2->do("CHANGE ${source_change} TO ${source_name}_DELAY=0");
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
