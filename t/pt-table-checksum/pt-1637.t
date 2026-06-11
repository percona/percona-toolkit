#!/usr/bin/env perl

BEGIN {
    die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
    unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
    unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
use Sandbox;
use SqlModes;
require "$trunk/bin/pt-table-checksum";

plan skip_all => 'Disabled until PT-2174 is fixed';

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);

diag ('Starting second sandbox source');
my ($source1_dbh, $source1_dsn) = $sb->start_sandbox(
   server => 'chan_source1',
   type   => 'source',
);

diag ('Starting second sandbox replica 1');
my ($replica1_dbh, $replica1_dsn) = $sb->start_sandbox(
   server => 'chan_replica1',
   type   => 'replica',
   source => 'chan_source1',
);

diag ('Starting second sandbox replica 2');
my ($replica2_dbh, $replica2_dsn) = $sb->start_sandbox(
   server => 'chan_replica2',
   type   => 'replica',
   source => 'chan_source1',
);

my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
    plan skip_all => 'Cannot connect to sandbox source';
}
else {
    plan tests => 2;
}

diag("loading samples");
$sb->load_file('chan_source1', 't/pt-table-checksum/samples/pt-1637.sql');


my @args = ($source1_dsn, 
    "--set-vars", "innodb_lock_wait_timeout=50", 
    "--ignore-databases", "mysql", "--no-check-binlog-format", 
    "--recursion-method", "dsn=h=127.0.0.1,D=test,t=dsns",
    "--run-time", "5", "--fail-on-stopped-replication",
);

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
$sb->do_as_root("chan_replica1", "stop ${replica_name} IO_thread;");

my $output;
my $exit_status;

($output, $exit_status) = full_output(
    sub { $exit_status = pt_table_checksum::main(@args) },
    stderr => 1,
);

is(
    $exit_status,
    128,
    "PT-1637 exist status 128 if replication is stopped and --fail-on-replication-stopped",
);

$sb->do_as_root("chan_replica1", "start ${replica_name} IO_thread;");
sleep(2);

$sb->stop_sandbox(qw(chan_source1 chan_replica2 chan_replica1));

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
