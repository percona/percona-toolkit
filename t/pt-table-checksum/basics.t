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

# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use Data::Dumper;
use PerconaTest;
use Sandbox;

# Fix @INC because pt-table-checksum uses subclass OobNibbleIterator.
shift @INC;  # our unshift (above)
shift @INC;  # PerconaTest's unshift
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !@{$master_dbh->selectall_arrayref('show databases like "sakila"')} ) {
   plan skip_all => 'sakila database is not loaded';
}
else {
   plan tests => 22;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3));
my $row;
my $output;
my $exit_status;
my $sample  = "t/pt-table-checksum/samples/";
my $outfile = '/tmp/pt-table-checksum-results';
my $repl_db = 'percona';

sub reset_repl_db {
   $master_dbh->do("drop database if exists $repl_db");
   $master_dbh->do("create database $repl_db");
   $master_dbh->do("use $repl_db");
}

$sb->wipe_clean($master_dbh);
diag(`rm $outfile >/dev/null 2>&1`);

# ############################################################################
# Default checksum and results.  The tool does not technically require any
# options on well-configured systems (which the test env cannot be).  With
# nothing but defaults, it should create the repl table, checksum and check
# all tables, dynamically adjust the chunk size, and throttle itself and based
# on all slaves' lag.  We don't explicitly test throttling here; that's done
# in throttle.t.
# ############################################################################

ok(
   no_diff(
      sub { pt_table_checksum::main(@args) },
      "$sample/default-results-5.1.txt",
      post_pipe => 'awk \'{print $2 " " $3 " " $4 " " $6 " " $8}\'',
   ),
   "Default checksum"
);

# On fast machines, the chunk size will probably be be auto-adjusted so
# large that all tables will be done in a single chunk without an index.
# Since this varies by default, there's no use checking the checksums
# other than to ensure that there's at one for each table.
$row = $master_dbh->selectrow_arrayref("select count(*) from percona.checksums");
cmp_ok(
   $row->[0], '>=', 37,
   'At least 37 checksums'
);

# ############################################################################
# Static chunk size (disable --chunk-time)
# ############################################################################

ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--chunk-time 0)) },
      "$sample/static-chunk-size-results-5.1.txt",
      post_pipe => 'awk \'{print $2 " " $3 " " $4 " " $5 " " $6 " " $8}\'',
   ),
   "Static chunk size (--chunk-time 0)"
);

$row = $master_dbh->selectrow_arrayref("select count(*) from percona.checksums");
is(
   $row->[0],
   86,
   '86 checksums on master'
);

$row = $slave_dbh->selectrow_arrayref("select count(*) from percona.checksums");
is(
   $row->[0],
   86,
   '86 checksums on slave'
);

# ############################################################################
# --[no]replicate-check and, implicitly, the tool's exit status.
# ############################################################################

# Make one row on the slave differ.
$row = $slave_dbh->selectrow_arrayref("select city, last_update from sakila.city where city_id=1");
$slave_dbh->do("update sakila.city set city='test' where city_id=1");

$exit_status = pt_table_checksum::main(@args,
   qw(--quiet --quiet -t sakila.city));

is(
   $exit_status,
   1,
   "--replicate-check on by default, detects diff"
);

$exit_status = pt_table_checksum::main(@args,
   qw(--quiet --quiet -t sakila.city --no-replicate-check));

is(
   $exit_status,
   0,
   "--no-replicate-check, no diff detected"
);

# Restore the row on the slave, else other tests will fail.
$slave_dbh->do("update sakila.city set city='$row->[0]', last_update='$row->[1]' where city_id=1");

# #############################################################################
# --[no]empty-replicate-table
# Issue 21: --empty-replicate-table doesn't empty if previous runs leave info
# #############################################################################

$sb->wipe_clean($master_dbh);
$sb->load_file('master', 't/pt-table-checksum/samples/issue_21.sql');

# Run once to populate the repl table.
pt_table_checksum::main(@args, qw(--quiet --quiet -t test.issue_21),
   qw(--chunk-time 0 --chunk-size 2));

# Insert two fake rows into the repl table.  The first row tests that
# --empty-replicate-table deletes all rows for each checksummed table,
# and the second row tests that if a table isn't checksummed, then its
# rows aren't deleted.
$master_dbh->do("INSERT INTO percona.checksums VALUES ('test', 'issue_21', 999, 0.00, 'idx', '0', '0', '0', 0, '0', 0, NOW())");
$master_dbh->do("INSERT INTO percona.checksums VALUES ('test', 'other_tbl', 1, 0.00, 'idx', '0', '0', '0', 0, '0', 0, NOW())");

pt_table_checksum::main(@args, qw(--quiet --quiet -t test.issue_21),
   qw(--chunk-time 0 --chunk-size 2));

$row = $master_dbh->selectall_arrayref("SELECT tbl, chunk FROM percona.checksums WHERE db='test' ORDER BY tbl, chunk");
is_deeply(
   $row,
   [
      [qw(issue_21  1)],
      [qw(issue_21  2)],
      [qw(issue_21  3)],
      [qw(issue_21  4)], # lower oob
      [qw(issue_21  5)], # upper oob
      # fake row for chunk 999 is gone
      [qw(other_tbl 1)], # this row is still here
   ],
   "--emptry-replicate-table on by default"
) or print STDERR Dumper($row);

# ############################################################################
# --[no]recheck
# ############################################################################

$exit_status = pt_table_checksum::main(@args,
   qw(--quiet --quiet --chunk-time 0 --chunk-size 100 -t sakila.city));

$slave_dbh->do("update percona.checksums set this_crc='' where db='sakila' and tbl='city' and (chunk=1 or chunk=6)");

ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--replicate-check-only)) },
      "$sample/no-recheck.txt",
   ),
   "--no-recheck (just --replicate-check)"
);

# ############################################################################
# Detect infinite loop.
# ############################################################################
$sb->load_file('master', "t/pt-table-checksum/samples/oversize-chunks.sql");

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t osc.t --chunk-size 10)) },
   stderr => 1,
);

like(
   $output,
   qr/infinite loop detected/,
   "Detects infinite loop"
);

# ############################################################################
# Oversize chunk.
# ############################################################################
ok(
   no_diff(
      sub { pt_table_checksum::main(@args,
         qw(-t osc.t2 --chunk-size 8 --explain --explain)) },
      "$sample/oversize-chunks.txt",
   ),
   "Upper boundary same as next lower boundary"
);

$output = output(
   sub { pt_table_checksum::main(@args,
      qw(-t osc.t2 --chunk-time 0 --chunk-size 8 --chunk-size-limit 1)) },
   stderr => 1,
);

is(
   PerconaTest::count_checksum_results($output, 'skipped'),
   2,
   "Skipped oversize chunks"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "Oversize chunks are not errors"
);

# ############################################################################
# Check slave table row est. if doing doing 1=1 on master table.
# ############################################################################
$master_dbh->do('truncate table percona.checksums');
$sb->load_file('master', "t/pt-table-checksum/samples/3tbl-resume.sql");
PerconaTest::wait_for_table($slave_dbh, 'test.t3', "id=26");

$master_dbh->do('set sql_log_bin=0');
$master_dbh->do('truncate table test.t1');
$master_dbh->do('set sql_log_bin=1');

$output = output(
   sub {
      $exit_status = pt_table_checksum::main(@args, qw(-d test --chunk-size 2)) 
   },
   stderr => 1,
);

like(
   $output,
   qr/Skipping table test.t1/,
   "Warns about skipping large slave table"
);

is_deeply(
   $master_dbh->selectall_arrayref("select distinct tbl from percona.checksums where db='test'"),
   [ ['t2'], ['t3'] ],
   "Does not checksum large slave table on master"
);

is_deeply(
   $slave_dbh->selectall_arrayref("select distinct tbl from percona.checksums where db='test'"),
   [ ['t2'], ['t3'] ],
   "Does not checksum large slave table on slave"
);

is(
   $exit_status,
   1,
   "Non-zero exit status"
);

is(
   PerconaTest::count_checksum_results($output, 'skipped'),
   0,
   "0 skipped"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "0 errors"
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   52,
   "52 rows checksummed"
);

# #############################################################################
# Crash if no host in DSN.
# https://bugs.launchpad.net/percona-toolkit/+bug/819450
# http://code.google.com/p/maatkit/issues/detail?id=1332
# #############################################################################

$output = output(
   sub { $exit_status =  pt_table_checksum::main(
   qw(--user msandbox --pass msandbox),
   qw(-S /tmp/12345/mysql_sandbox12345.sock --lock-wait-timeout 3)) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "No host in DSN, zero exit status"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "No host in DSN, 0 errors"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
