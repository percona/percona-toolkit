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

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);

diag ('Starting second sandbox master');
my ($master1_dbh, $master1_dsn) = $sb->start_sandbox(
   server => 'chan_master1',
   type   => 'master',
);

diag ('Starting second sandbox slave 1');
my ($slave1_dbh, $slave1_dsn) = $sb->start_sandbox(
   server => 'chan_slave1',
   type   => 'slave',
   master => 'chan_master1',
);

diag ('Starting second sandbox slave 2');
my ($slave2_dbh, $slave2_dsn) = $sb->start_sandbox(
   server => 'chan_slave2',
   type   => 'slave',
   master => 'chan_master1',
);

my $dbh = $sb->get_dbh_for('chan_master1');

if ( !$dbh ) {
    plan skip_all => 'Cannot connect to sandbox master';
}
else {
    plan tests => 2;
}

diag("loading samples");
$sb->load_file('chan_master1', 't/pt-table-checksum/samples/pt-1637.sql');


my @args = ($master1_dsn, 
    "--set-vars", "innodb_lock_wait_timeout=50", 
    "--ignore-databases", "mysql", "--no-check-binlog-format", 
    "--recursion-method", "dsn=h=127.0.0.1,D=test,t=dsns",
    "--run-time", "5", "--fail-on-stopped-replication",
);

diag(join(" ", @args));

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
my $master_dsn = $sb->dsn_for('master');
$sb->do_as_root("chan_slave1", 'stop slave IO_thread;');

my $output;
my $exit_status;

$output = output(
    sub { $exit_status = pt_table_checksum::main(@args) },
    stderr => 1,
);
diag($output);

is(
    $exit_status,
    0,
    "PT-1616 pt-table-cheksum before --resume with binary fields exit status",
);

$sb->stop_sandbox('chan_master1');
$sb->stop_sandbox('chan_slave1');
$sb->stop_sandbox('chan_slave2');
# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
