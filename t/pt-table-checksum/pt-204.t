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
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
    plan skip_all => 'Cannot connect to sandbox master';
} elsif (!$sb->has_engine('master', 'ROCKSDB')) {
    plan skip_all => 'These tests need RocksDB';
} else {
    plan tests => 9;
}

$sb->load_file('master', 't/pt-table-checksum/samples/pt-204.sql');

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = $sb->dsn_for('master');
my @args       = ($master_dsn, "--set-vars", "innodb_lock_wait_timeout=50", 
                               "--no-check-binlog-format"); 
my ($output, $exit_status);

# Test #1 
($output, $exit_status) = full_output(
   sub { $exit_status = pt_table_checksum::main(@args) },
   stderr => 1,
);

diag("status: $exit_status");

is(
   $exit_status,
   64,
   "PT-204 Cannot checksum RocksDB tables. Exit status=64 -> SKIP_TABLE",
);

like(
    $output,
    qr/Checking if all tables can be checksummed/,
    "PT-204 Message before checksum starts",
);

like(
    $output,
    qr/The RocksDB storage engine is not supported with pt-table-checksum/,
    "PT-204 Error message: cannot checksum RocksDB tables",
);

# Test #2
($output, $exit_status) = full_output(
   sub { $exit_status = pt_table_checksum::main(@args, qw(--ignore-tables test.t1)) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "PT-204 Starting checksum since RocksDB table was skipped with --ignore-tables",
);

like(
    $output,
    qr/Starting checksum/,
    'PT-204 Got "Starting checksum" message',
);

unlike(
    $output,
    qr/test.t1/,
    "PT-204 RocksDB table was really skipped with --ignore-tables",
);

# Test #3
($output, $exit_status) = full_output(
   sub { $exit_status = pt_table_checksum::main(@args, qw(--ignore-engines RocksDB)) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "PT-204 Starting checksum since RocksDB table was skipped with --ignore-engines",
);

unlike(
    $output,
    qr/test.t1/,
    "PT-204 RocksDB table was really skipped with --ignore-engines",
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
