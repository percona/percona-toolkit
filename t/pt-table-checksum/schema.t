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
   plan tests => 30;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf 127.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/before.sql');

# Check --schema
$output = `$cmd --tables checksum_test --checksum --schema 2>&1`;
my $checksum = $sandbox_version ge '5.1' ? '3688961686' : '2752458186';
like(
   $output,
   qr/$checksum\s+127.1.test2.checksum_test/,
   '--checksum --schema'
);

# Should output the same thing, it only lacks the AUTO_INCREMENT specifier
# which is removed by the code before the schema is checksummed so the two
# tables end up having the same checksum.
like(
   $output,
   qr/$checksum\s+127.1.test.checksum_test/,
   '--checksum --schema, AUTO_INCREMENT removed'
);

$output = `$cmd --schema -d test -t checksum_test 2>&1`;
like(
   $output,
qr/
DATABASE\s+TABLE\s+CHUNK\s+HOST\s+ENGINE\s+COUNT\s+CHECKSUM\s+TIME\s+WAIT\s+STAT\s+LAG\n
test\s+checksum_test\s+0\s+127.1\s+MyISAM\s+NULL\s+$checksum\s+0\s+0\s+NULL\s+NULL\n
/x,
   "Checksum --schema"
);

# #############################################################################
# Issue 5: Add ability to checksum table schema instead of data
# #############################################################################

# The following --schema tests are sensitive to what schemas exist on the
# sandbox server. The sample file is for a blank server, i.e. just the mysql
# db and maybe or not the sakila db.
$sb->wipe_clean($master_dbh);

my $awk_slice = "awk '{print \$1,\$2,\$7}'";

# This test is too flaky because it depends on MySQL version and mysql
# tables.  The 3 tests above accomplish the same thing more deterministically:
# testing that we can checksum schema.
# my $ret_val = system("$cmd P=12346 --ignore-databases sakila --schema | $awk_slice | diff $trunk/t/pt-table-checksum/samples/sample_schema_opt -");
# cmp_ok($ret_val, '==', 0, '--schema basic output');

$output = `$cmd --schema --quiet`;
is(
   $output,
   '',
   '--schema respects --quiet'
);

$output = `$cmd --schema --ignore-databases mysql,sakila`;
is(
   $output,
   '',
   '--schema respects --ignore-databases'
);

$output = `$cmd --schema --ignore-tables users`;
unlike(
   $output,
   qr/users/,
   '--schema respects --ignore-tables'
);

# Remember to add $#opt_combos+1 number of tests to line 30.
my @opt_combos = ( # --schema and
   '--algorithm=BIT_XOR',
   '--algorithm=ACCUM',
   '--chunk-size=1M',
   '--count',
   '--crc',
   '--empty-replicate-table',
   '--float-precision=3',
   '--function=FNV_64',
   '--lock',
   '--optimize-xor',
   '--probability=1',
   '--replicate-check=1000',
   '--replicate=checksum_tbl',
   '--resume samples/resume01_partial.txt',
   '--since \'"2008-01-01" - interval 1 day\'',
   '--sleep=1000',
   '--wait=1000',
   '--where="id > 1000"',
);

foreach my $opt_combo ( @opt_combos ) {
   $output = `$cmd P=12346 --ignore-databases sakila --schema $opt_combo 2>&1`;
   my ($other_opt) = $opt_combo =~ m/^([\w-]+\b)/;
   like(
      $output,
      qr/--schema is not allowed with $other_opt/,
      "--schema is not allowed with $other_opt"
   );
}
# Have to do this one manually be --no-verify is --verify in the
# error output which confuses the regex magic for $other_opt.
$output = `$cmd P=12346 --ignore-databases sakila --schema --no-verify 2>&1`;
like(
   $output,
   qr/--schema is not allowed with --verify/,
   "--schema is not allowed with --[no]verify"
);

# Check that --schema does NOT lock by default
$output = `MKDEBUG=1 $cmd P=12346 --schema 2>&1`;
unlike($output, qr/LOCK TABLES /, '--schema does not lock tables by default');

$output = `MKDEBUG=1 $cmd P=12346 --schema --lock 2>&1`;
unlike($output, qr/LOCK TABLES /, '--schema does not lock tables even with --lock');

# #############################################################################
# Test issue 5 + 35: --schema a missing table
# #############################################################################
$sb->create_dbs($master_dbh, [qw(test)]);
diag(`/tmp/12345/use -e 'SET SQL_LOG_BIN=0; CREATE TABLE test.only_on_master(a int);'`);

$output = `$cmd P=12346 -t test.only_on_master --schema 2>&1`;
$checksum = $sandbox_version ge '5.1' ? '2402764438' : '23678842';
like($output, qr/MyISAM\s+NULL\s+$checksum/, 'Table on master checksummed with --schema');
like($output, qr/MyISAM\s+NULL\s+NULL/, 'Missing table on slave checksummed with --schema');
like($output, qr/test.only_on_master does not exist on slave 127\.1:12346/, 'Debug reports missing slave table with --schema');

diag(`/tmp/12345/use -e 'DROP TABLE IF EXISTS test.only_on_master'`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
