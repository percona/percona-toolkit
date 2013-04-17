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
use Data::Dumper;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-sync";

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 9;
}

my $sample     = "t/pt-table-sync/samples";
my $master_dsn = "h=127.1,P=12345,u=msandbox,p=msandbox";
my $slave_dsn  = "h=127.1,P=12346,u=msandbox,p=msandbox";

# #############################################################################
# 
# #############################################################################

$sb->load_file('master', "$sample/wrong-tbl-struct-bug-1003014.sql");

# Make a diff in each table.
$slave_dbh->do("DELETE FROM test.aaa WHERE STOP_ARCHIVE IN (5,6,7)");
$slave_dbh->do("UPDATE test.zzz SET c='x' WHERE id IN (44,45,46)");

$output = `$trunk/bin/pt-table-checksum $master_dsn --set-vars innodb_lock_wait_timeout=3 --max-load '' -d test --chunk-size 10 2>&1`;

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   2,
   "Bug 1003014 (wrong tbl_struct): 2 diffs"
) or print STDERR $output;

my $checksums = [
   [qw( test aaa 1 )],
   [qw( test zzz 1 )],
   [qw( test zzz 2 )],
   [qw( test zzz 3 )],
   [qw( test zzz 4 )],
   [qw( test zzz 5 )],
   [qw( test zzz 6 )],
   [qw( test zzz 7 )],
   [qw( test zzz 8 )],
   [qw( test zzz 9 )],
   [qw( test zzz 10 )],
   [qw( test zzz 11 )],
   [qw( test zzz 12 )],
   [qw( test zzz 13 )],
   [qw( test zzz 14 )],
];

my $rows = $master_dbh->selectall_arrayref("SELECT db, tbl, chunk FROM percona.checksums ORDER BY db, tbl, chunk");
is_deeply(
   $rows,
   $checksums,
   "Bug 1003014 (wrong tbl_struct): checksums"
);

my $exit_status;
$output = output(
   sub { $exit_status = pt_table_sync::main($slave_dsn,
      qw(--replicate percona.checksums --sync-to-master --print --execute),
      "--tables", "test.aaa,test.zzz") },
   stderr => 1,
);
$sb->wait_for_slaves();

is(
   $exit_status,
   2,  # rows synced OK; 3=error (1) & rows synced (2)
   "Bug 1003014 (wrong tbl_struct): 0 exit"
) or diag($output);

$rows = $slave_dbh->selectall_arrayref("SELECT c FROM test.zzz WHERE id IN (44,45,46)");
is_deeply(
   $rows,
   [ ['a'], ['a'], ['a'] ],
   "Bug 1003014 (wrong tbl_struct): synced rows"
);

# #########################################################################
# Repeat the whole process without --sync-to-master so the second code path
# in sync_via_replication() is tested.
# #########################################################################

$sb->wipe_clean($master_dbh);
$sb->load_file('master', "$sample/wrong-tbl-struct-bug-1003014.sql");

$slave_dbh->do("DELETE FROM test.aaa WHERE STOP_ARCHIVE IN (5,6,7)");
$slave_dbh->do("UPDATE test.zzz SET c='x' WHERE id IN (44,45,46)");

$output = `$trunk/bin/pt-table-checksum $master_dsn --set-vars innodb_lock_wait_timeout=3 --max-load '' -d test --chunk-size 10 2>&1`;

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   2,
   "Bug 1003014 (wrong tbl_struct): 2 diffs (just replicate)"
) or print STDERR $output;

$rows = $master_dbh->selectall_arrayref("SELECT db, tbl, chunk FROM percona.checksums ORDER BY db, tbl, chunk");
is_deeply(
   $rows,
   $checksums,
   "Bug 1003014 (wrong tbl_struct): checksums (just replicate)"
);

$output = output(
   sub { $exit_status = pt_table_sync::main($master_dsn,
      qw(--replicate percona.checksums --print --execute),
      "--tables", "test.aaa,test.zzz") },
   stderr => 1,
);
$sb->wait_for_slaves();

is(
   $exit_status,
   2,  # rows synced OK; 3=error (1) & rows synced (2)
   "Bug 1003014 (wrong tbl_struct): 0 exit (just replicate)"
) or diag($output);

$rows = $slave_dbh->selectall_arrayref("SELECT c FROM test.zzz WHERE id IN (44,45,46)");
is_deeply(
   $rows,
   [ ['a'], ['a'], ['a'] ],
   "Bug 1003014 (wrong tbl_struct): synced rows (just replicate)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
