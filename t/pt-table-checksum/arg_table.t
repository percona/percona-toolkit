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
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 6;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf -d test -t checksum_test 127.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/before.sql');

# Check --since with --arg-table. The value in the --arg-table table
# ought to override the --since passed on the command-line.
$output = `$cmd --arg-table test.argtest --since 20 --explain 2>&1`;
unlike($output, qr/`a`>='20'/, 'Argtest overridden');
like($output, qr/`a`>='1'/, 'Argtest set to something else');

# Make sure that --arg-table table has only legally allowed columns in it
$output = `$cmd --arg-table test.argtest2 2>&1`;
like($output, qr/Column foobar .from test.argtest2/, 'Argtest with bad column');

# #############################################################################
# Issue 467: overridable arguments with --arg-table
# #############################################################################

# This block of actions is historical, before mk-table-checksum.t
# was modularized.  In some forgotten way, it sets up the conditions
# for the actual test below.
$sb->load_file('master', 't/pt-table-checksum/samples/issue_122.sql');
$sb->load_file('master', 't/pt-table-checksum/samples/issue_94.sql');
`$cmd --arg-table test.argtable --save-since -d test -t issue_122 --chunk-size 2`;
$master_dbh->do("INSERT INTO test.issue_122 VALUES (null,'a'),(null,'b')");
`$cmd --arg-table test.argtable --save-since -d test -t issue_122 --chunk-size 2`;
$master_dbh->do('ALTER TABLE test.argtable ADD COLUMN (modulo INT, offset INT, `chunk-size` INT)');
$master_dbh->do("TRUNCATE TABLE test.argtable");

# Two different args for two different tables.  Because issue_122 uses
# --chunk-size, it will use the BIT_XOR algo.  And issue_94 uses no opts
# so it will use the CHECKSUM algo.
$master_dbh->do("INSERT INTO test.argtable (db, tbl, since, modulo, offset, `chunk-size`) VALUES ('test', 'issue_122', NULL, 2, 1, 2)");
$master_dbh->do("INSERT INTO test.argtable (db, tbl, since, modulo, offset, `chunk-size`) VALUES ('test', 'issue_94', NULL, NULL, NULL, NULL)");
$master_dbh->do("INSERT INTO test.issue_122 VALUES (3,'c'),(4,'d'),(5,'e'),(6,'f'),(7,'g'),(8,'h'),(9,'i'),(10,'j')");

$output = `$cmd -d test -t issue_122,issue_94 --arg-table test.argtable | diff $trunk/t/pt-table-checksum/samples/issue_467.txt -`;
is(
   $output,
   '',
   'chunk-size, modulo and offset in argtable (issue 467)'
);

# #############################################################################
# Issue 922: mk-table-checksum --arg-table causes false positive results
# #############################################################################
SKIP: {
   skip 'issue 922', 2 unless $slave_dbh;

   $sb->wipe_clean($master_dbh);
   $sb->create_dbs($master_dbh, [qw(test)]);
   $sb->load_file('master', "t/pt-table-checksum/samples/issue_922.sql");
   $sb->load_file('master', "t/pt-table-checksum/samples/arg-table.sql");

   $master_dbh->do('insert into test.args values ("test", "t")');

   is_deeply(
      $master_dbh->selectall_arrayref('select * from test.t order by i'),
      [[1,'aa'],[2,'ab'],[3,'ac'],[4,'ad'],[5,'zz'],[6,'zb']],
      'Master has all rows'
   );

   is_deeply(
      $slave_dbh->selectall_arrayref('select * from test.t order by i'),
      [[1,'aa'],[2,'ab'],[3,'ac'],[4,'ad']],
      'Slave missing 2 rows'
   );
}

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
