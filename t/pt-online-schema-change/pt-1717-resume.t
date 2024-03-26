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

my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh1 = $sb->get_dbh_for('slave1');
my $slave_dbh2 = $sb->get_dbh_for('slave2');
my $master_dsn = 'h=127.0.0.1,P=12345,u=msandbox,p=msandbox';
my $slave_dsn1 = 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox';
my $slave_dsn2 = 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox';
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
    return if ($sandbox_version >= '8.0');
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
   # stop slave 12347
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
   $sb->wait_for_slaves();

   diag("Setting slave delay to $delay seconds");
   diag(`/tmp/12345/use -N test -e "DROP TABLE IF EXISTS pt1717_back"`);

   $slave_dbh1->do('STOP SLAVE');
   $slave_dbh1->do("CHANGE MASTER TO MASTER_DELAY=$delay");
   $slave_dbh1->do('START SLAVE');

   # Run a full table scan query to ensure the slave is behind the master
   # There is no query cache in MySQL 8.0+
   reset_query_cache($master_dbh, $master_dbh);
   # Update one row so slave is delayed
   $master_dbh->do('UPDATE `test`.`pt1717` SET f2 = f2 + 1 LIMIT 1');
   $master_dbh->do('UPDATE `test`.`pt1717` SET f2 = f2 + 1 WHERE f1 = ""');

   # Creating copy of table pt1717, so we can compare data later
   diag(`/tmp/12345/use -N test -e "CREATE TABLE pt1717_back like pt1717"`);
   diag(`/tmp/12345/use -N test -e "INSERT INTO pt1717_back SELECT * FROM pt1717"`);
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
$sb->load_file('master', "t/pt-online-schema-change/samples/pt-1717.sql");

# Should be greater than chunk-size and big enough, so pt-osc will wait for delay
my $num_rows = 5000;
my $chunk_size = 10;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt1717 $num_rows`);

diag("Starting tests...");

set_delay();

# We need to sleep, otherwise pt-osc can finish before slave is delayed
sleep($max_lag);

my $args = "$master_dsn,D=test,t=pt1717 --execute --chunk-size ${chunk_size} --max-lag $max_lag --alter 'engine=INNODB' --pid $tmp_file_name --progress time,5 --no-drop-new-table --no-drop-triggers --history";

$output = run_broken_job($args);

like(
   $output,
   qr/`test`.`pt1717` was not altered/s,
   "pt-osc stopped with error as expected",
) or diag($output);

diag(`/tmp/12347/start >/dev/null`);
$sb->wait_for_slaves();

$output = `/tmp/12345/use -N -e "select job_id, upper_boundary from percona.pt_osc_history"`;
my ($job_id, $upper_boundary) = split(/\s+/, $output);

my $copied_rows = `/tmp/12345/use -N -e "select count(*) from test._pt1717_new"`;
chomp($copied_rows);

ok(
   $copied_rows eq $upper_boundary,
   'Upper chunk boundary stored correctly'
) or diag("Copied_rows: ${copied_rows}, upper boundary: ${upper_boundary}");;

my @args = (qw(--execute --chunk-size=10 --history));

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=pt1717",
         '--alter', 'engine=INNODB', '--execute', "--resume=${job_id}",
         '--chunk-index=f2'
         ) }
);

is(
   $exit,
   17,
   'pt-osc --resume correctly fails if --chunk-index is different from the --chunk-index in the stored job'
) or diag($exit);

like(
   $output,
   qr/User-specified chunk index does not match stored one/i,
   'Error message printed for the different --chunk-index option'
) or diag($output);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=pt1717",
         '--max-lag', $max_lag,
         '--resume', $job_id,
         '--alter', 'engine=INNODB',
         '--plugin', "$plugin/pt-1717.pm",
         ),
      },
);

$output =~ /.*Chunk: (\d+)\n/ms;
my $last_chunk = int($1);

ok(
   $last_chunk * $chunk_size + int($copied_rows) == $num_rows,
   'Tool inserted only missed rows in the second run'
) or diag("Last chunk: ${last_chunk}, copied rows: ${copied_rows}");

my $new_table_checksum = diag(`/tmp/12345/use test -N -e "CHECKSUM TABLE pt1717"`);
my $old_table_checksum = diag(`/tmp/12345/use test -N -e "CHECKSUM TABLE pt1717_back"`);

ok(
   $new_table_checksum eq $old_table_checksum,
   'All rows copied correctly'
) or diag("New table checksum: '${new_table_checksum}', original content checksum: '${old_table_checksum}'");

# Tests for chunk-index and chunk-index-columns options
$args = "$master_dsn,D=test,t=pt1717 --alter engine=innodb --execute --history --chunk-size=10 --no-drop-new-table --no-drop-triggers --reverse-triggers --chunk-index=f2";

set_delay();
$output = run_broken_job($args);
diag(`/tmp/12347/start >/dev/null`);

$output =~ /History saved. Job id: (\d+)/ms;
$job_id = $1;

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=pt1717",
         '--alter', 'engine=innodb', '--execute', "--resume=${job_id}",
         ) }
);

is(
   $exit,
   17,
   'pt-osc --resume correctly fails if --chunk-index option not specified for the job run with custom --chunk-index'
) or diag($exit);

like(
   $output,
   qr/User-specified chunk index does not match stored one/i,
   'Error message printed for the missed --chunk-index option'
) or diag($output);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=pt1717",
         '--alter', 'engine=innodb', '--execute', "--resume=${job_id}",
         '--chunk-index=f1'
         ) }
);

is(
   $exit,
   17,
   'pt-osc --resume correctly fails if --chunk-index is different from the --chunk-index in the stored job'
) or diag($exit);

like(
   $output,
   qr/User-specified chunk index does not match stored one/i,
   'Error message printed for the different --chunk-index option'
) or diag($output);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=pt1717",
         '--alter', 'engine=innodb', '--execute', "--resume=${job_id}",
         '--chunk-index=f2', '--chunk-index-columns=1'
         ) }
);

is(
   $exit,
   17,
   'pt-osc --resume correctly fails if --chunk-index-columns is different from the --chunk-index-columns in the stored job'
) or diag($exit);

like(
   $output,
   qr/User-specified chunk index does not match stored one/i,
   'Error message printed for the different --chunk-index-columns option'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.tables where TABLE_SCHEMA='test' and table_name like '%pt1717%' and table_name != 'pt1717_back'"`;

is(
   $output + 0,
   2,
   'Table was not dropped'
);

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.triggers where TRIGGER_SCHEMA='test' AND EVENT_OBJECT_TABLE='pt1717' AND trigger_name NOT LIKE 'rt_%'"`;

is(
   $output + 0,
   3,
   'Triggers were not dropped'
);

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.triggers where TRIGGER_SCHEMA='test' AND EVENT_OBJECT_TABLE like '%pt1717%_new' AND trigger_name LIKE 'rt_%'"`;

is(
   $output + 0,
   3,
   'Reverse triggers were not dropped'
);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=pt1717",
         '--alter', 'engine=innodb', '--execute', "--resume=${job_id}",
         '--chunk-size=4',
         '--chunk-index=f2'
      ) }
);

is(
   $exit,
   0,
   'pt-osc --resume finishes correctly if --chunk-index option points to the same index as previous job run'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.tables where TABLE_SCHEMA='test' and table_name like '%pt1717%' and table_name != 'pt1717_back'"`;

is(
   $output + 0,
   1,
   'Table was dropped after successful change'
);

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.triggers where TRIGGER_SCHEMA='test' AND EVENT_OBJECT_TABLE = 'pt1717' AND TRIGGER_NAME NOT LIKE 'rt_%'"`;

is(
   $output + 0,
   0,
   'Triggers were dropped after successful change'
);

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.triggers where TRIGGER_SCHEMA='test' AND EVENT_OBJECT_TABLE = 'pt1717' AND TRIGGER_NAME LIKE 'rt_%'"`;

is(
   $output + 0,
   3,
   'Reverse triggers were dropped after successful change'
);

$new_table_checksum = diag(`/tmp/12345/use test -N -e "CHECKSUM TABLE pt1717"`);
$old_table_checksum = diag(`/tmp/12345/use test -N -e "CHECKSUM TABLE pt1717_back"`);

ok(
   $new_table_checksum eq $old_table_checksum,
   'All rows copied correctly'
) or diag("New table checksum: '${new_table_checksum}', original content checksum: '${old_table_checksum}'");

`/tmp/12345/use test -N -e "UPDATE percona.pt_osc_history SET done = 'no' where job_id='${job_id}'"`;

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=pt1717",
         '--alter', 'engine=innodb', '--execute', "--resume=${job_id}",
         '--chunk-size=4',
         '--chunk-index=f2'
      ) }
);

is(
   $exit,
   17,
   '--resume expectedly fails when new table does not exists'
);

like(
   $output,
   qr/New table `test`.`[_]+pt1717_new` not found, restart operation from scratch/i,
   'Correct error message printed for the missed new table'
) or diag($output);

$output =~ /New table `test`.`([_]+pt1717_new)` not found, restart operation from scratch/i;

`/tmp/12345/use test -N -e "CREATE TABLE $1 LIKE pt1717"`;

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=pt1717",
         '--alter', 'engine=innodb', '--execute', "--resume=${job_id}",
         '--chunk-size=4',
         '--chunk-index=f2'
      ) }
);

is(
   $exit,
   17,
   '--resume expectedly fails when triggers do not exists'
);

like(
   $output,
   qr/Trigger test.pt_osc_test_pt1717_\w{3} not found, restart operation from scratch to avoid data loss/i,
   'Correct error message printed for the missed triggers'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
diag("Cleaning");
$slave_dbh2 = $sb->get_dbh_for('slave2');
diag("Setting slave delay to 0 seconds");
$slave_dbh1->do('STOP SLAVE');
$slave_dbh2->do('STOP SLAVE');
$master_dbh->do('RESET MASTER');
$slave_dbh1->do('RESET MASTER');
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
