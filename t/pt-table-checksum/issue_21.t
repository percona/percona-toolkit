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

use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

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
   plan tests => 5;
}

my $output;
my $ret_val;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf 127.0.0.1";

$sb->wipe_clean($master_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 21: --empty-replicate-table doesn't empty if previous runs leave info
# #############################################################################

# This test requires that the test db has only the table created by
# issue_21.sql. If there are other tables, the first test below
# will fail because samples/basic_replicate_output will differ.
$sb->load_file('master', 't/pt-table-checksum/samples/checksum_tbl.sql');
$sb->load_file('master', 't/pt-table-checksum/samples/issue_21.sql');

# Run --replication once to populate test.checksum.
$ret_val = system("$cmd -d test --replicate test.checksum | diff $trunk/t/pt-table-checksum/samples/basic_replicate_output -");
# Might as well test this while we're at it.
cmp_ok($ret_val >> 8, '==', 0, 'Basic --replicate works');

# Insert a bogus row into test.checksum.
diag(`/tmp/12345/use -e "INSERT INTO test.checksum VALUES ('foo', 'bar', 0, 'a', 'b', 0, 'c', 0,  NOW())"`);

# Run --replicate again which should completely clear test.checksum,
# including our bogus row.
`$cmd --replicate test.checksum -d test --empty-replicate-table >/dev/null`;

# Make sure bogus row is actually gone.
$output = `/tmp/12345/use -e "SELECT db FROM test.checksum WHERE db = 'foo'"`;
unlike($output, qr/foo/, '--empty-replicate-table completely empties the table (fixes issue 21)');

# While we're at it, let's test what the doc says about --empty-replicate-table:
# "Ignored if L<"--replicate"> is not specified."
diag(`/tmp/12345/use -e "INSERT INTO test.checksum VALUES ('foo', 'bar', 0, 'a', 'b', 0, 'c', 0,  NOW())"`);
`$cmd P=12346 --empty-replicate-table >/dev/null`;

# Now make sure bogus row is still present.
$output = `/tmp/12345/use -e "SELECT db FROM test.checksum WHERE db = 'foo';"`;
like($output, qr/foo/, '--empty-replicate-table is ignored if --replicate is not specified');

diag(`/tmp/12345/use -e "DELETE FROM test.checksum WHERE db = 'foo'"`);

# Screw up the data on the slave and make sure --replicate-check works
$slave_dbh->do("update test.checksum set this_crc='' where test.checksum.tbl = 'issue_21'");

# Can't use $cmd here; see http://code.google.com/p/maatkit/issues/detail?id=802
$output = `$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox -d test --replicate test.checksum --replicate-check 1 2>&1`;
like($output, qr/issue_21/, '--replicate-check works');

cmp_ok($CHILD_ERROR>>8, '==', 1, 'Exit status is correct with --replicate-check failure');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
