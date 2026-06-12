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

if ($ENV{PERCONA_SLOW_BOX}) {
    plan skip_all => 'This test needs a fast machine';
} elsif ($sandbox_version lt '5.7') {
    plan skip_all => 'This tests needs MySQL 5.7+';
}

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

if ($sb->is_cluster_mode) {
    plan skip_all => 'Not for PXC';
} else {
    plan tests => 3;
}                                  

my $source_dbh = $sb->get_dbh_for("source");
my $source_dsn = $sb->dsn_for("source");

my $replica1_dbh = $sb->get_dbh_for("replica1");
my $replica1_dsn = $sb->dsn_for("replica1");

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;

# We need to reset source, because otherwise later RESET REPLICA call
# will let sandbox to re-apply all previous events, executed on the sandbox.
$source_dbh->do("RESET ${source_reset}");

if ( $sandbox_version ge '8.4' ) {
    diag("Setting replication filters on replica 2");
    $sb->load_file('replica2', "t/pt-online-schema-change/samples/pt-1455_replica.sql", undef, no_wait => 1);
    diag("Setting replication filters on replica 1");
    $sb->load_file('replica1', "t/pt-online-schema-change/samples/pt-1455_replica.sql", undef, no_wait => 1);
    
}
else {
    diag("Setting replication filters on replica 2");
    $sb->load_file('replica2', "t/pt-online-schema-change/samples/pt-1455_slave.sql", undef, no_wait => 1);
    diag("Setting replication filters on replica 1");
    $sb->load_file('replica1', "t/pt-online-schema-change/samples/pt-1455_slave.sql", undef, no_wait => 1);
}
diag("Setting replication filters on source");
$sb->load_file('source', "t/pt-online-schema-change/samples/pt-1455_source.sql");
diag("replication filters set");

my $num_rows = 1000;
my $source_port = 12345;

diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=$source_port --user=msandbox --password=msandbox employees t1 $num_rows`);
diag("$num_rows rows loaded. Starting tests.");

$source_dbh->do("FLUSH TABLES");
$sb->wait_for_replicas();

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args, "$source_dsn,D=employees,t=t1",
            '--execute', '--no-check-replication-filters', 
            '--alter', "engine=innodb",
        ),
    },
    stderr => 1,
);

is(
    $exit_status,
    0,
    "PT-1455 Successfully altered. Exit status = 0",
);

like(
    $output,
    qr/Successfully altered/s,
    "PT-1455 Got successfully altered message.",
);
$source_dbh->do("RESET ${source_reset}");
$source_dbh->do("DROP DATABASE IF EXISTS employees");

diag("Resetting replication filters on replica 2");
if ( $sandbox_version ge '8.4' ) {
    $sb->load_file('replica2', "t/pt-online-schema-change/samples/pt-1455_reset_replica.sql", undef, no_wait => 1);
    diag("Resetting replication filters on replica 1");
    $sb->load_file('replica1', "t/pt-online-schema-change/samples/pt-1455_reset_replica.sql", undef, no_wait => 1);
}
else {
    $sb->load_file('replica2', "t/pt-online-schema-change/samples/pt-1455_reset_slave.sql", undef, no_wait => 1);
    diag("Resetting replication filters on replica 1");
    $sb->load_file('replica1', "t/pt-online-schema-change/samples/pt-1455_reset_slave.sql", undef, no_wait => 1);
}
$sb->wait_for_replicas();

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
