#!/usr/bin/env perl

BEGIN {
    die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
    unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
    unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;
use threads::shared;
use Thread::Semaphore;

use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempdir /;

if ($sandbox_version lt '5.7') {
    plan skip_all => 'This test needs MySQL 5.7+';
} else {
    plan tests => 3;
}    

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

my $dbh = $sb->get_dbh_for('source');
my $dsn = $sb->dsn_for("source");

my $replica_dbh = $sb->get_dbh_for('replica1');

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $source_port = $sb->port_for('source');
my $num_rows = 5000;

$sb->load_file('source', "t/pt-online-schema-change/samples/pt-1757.sql");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=$source_port --user=msandbox --password=msandbox test t1 $num_rows`);


# Let's alter the stats to force this scenario:
# 1) On source, we are going to put 100 as the number of rows in the table. This will make osc to try to run in one chunk
# 2) On the replica, we are going to put the real number of rows. This will cause a fallback to nibble and pt-osc should call
# NibbleIterator->switch_to_nibble()

$dbh->do('SET @@SESSION.sql_log_bin=0');
$dbh->do('update mysql.innodb_table_stats set n_rows=100 where table_name="t1"');
$dbh->do('update mysql.innodb_index_stats set stat_value=100 where stat_description in("id") and table_name="t1"');
$dbh->do('SET @@SESSION.sql_log_bin=1');

$replica_dbh->do('SET @@SESSION.sql_log_bin=0');
$replica_dbh->do("update mysql.innodb_table_stats set n_rows=$num_rows where table_name='t1'");
$replica_dbh->do("update mysql.innodb_index_stats set stat_value=$num_rows where stat_description in('id') and table_name='t1'");
$replica_dbh->do('SET @@SESSION.sql_log_bin=1');

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args, "$dsn,D=test,t=t1",
            '--execute', '--alter', "ADD COLUMN new_col INT NOT NULL DEFAULT 1",
            '--chunk-size', '25',
        ),
    },
    stderr => 1,
);

is(
    $exit_status,
    0,
    "Altered OK status",
);

# The WHERE clause here is important as a double check that the table was altered and new_col exists
my $rows = $dbh->selectrow_arrayref("SELECT COUNT(*) FROM test.t1 WHERE new_col = 1");
is(
   $rows->[0],
   $num_rows,
   "Correct rows count"
) or diag(Dumper($rows));

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
