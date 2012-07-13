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
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( PerconaTest::load_data_is_disabled($dbh) ) {
   diag("LOAD DATA LOCAL INFILE is disabled, only going to test the error message");
   plan tests => 2;
}
else {
   plan tests => 11;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-archiver";

if ( PerconaTest::load_data_is_disabled($dbh) ) {
   test_disabled_load_data($dbh, $sb);
}
else {

$sb->wipe_clean($dbh);
$sb->create_dbs($dbh, ['test']);

# Test --bulk-insert
$sb->load_file('master', 't/pt-archiver/samples/table5.sql');
$dbh->do('INSERT INTO `test`.`table_5_copy` SELECT * FROM `test`.`table_5`');

$output = output(
   sub { pt_archiver::main(qw(--no-ascend --limit 50 --bulk-insert),
      qw(--bulk-delete --where 1=1 --statistics),
      '--source', "D=test,t=table_5,F=$cnf",
      '--dest',   "t=table_5_dest") },
);
like($output, qr/SELECT 105/, 'Fetched 105 rows');
like($output, qr/DELETE 105/, 'Deleted 105 rows');
like($output, qr/INSERT 105/, 'Inserted 105 rows');
like($output, qr/bulk_deleting *3 /, 'Issued only 3 DELETE statements');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_5"`;
is($output + 0, 0, 'Bulk delete removed all rows');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_5_dest"`;
is($output + 0, 105, 'Bulk insert works');

# Check that the destination table has the same data as the source
$output = `/tmp/12345/use -N -e "checksum table test.table_5_dest, test.table_5_copy"`;
my ( $chks ) = $output =~ m/dest\s+(\d+)/;
like($output, qr/copy\s+$chks/, 'copy checksum');


# ############################################################################
# Issue 1260: mk-archiver --bulk-insert data loss
# ############################################################################
$sb->load_file('master', 't/pt-archiver/samples/bulk_regular_insert.sql');
$output = output(
   sub { pt_archiver::main(
       '--where', "id < 8", qw(--limit 100000 --txn-size 1000),
       qw(--why-quit --statistics --bulk-insert),
      '--source', "D=bri,t=t,F=$cnf",
      '--dest',   "t=t_arch") },
);
$rows = $dbh->selectall_arrayref('select id from bri.t order by id');
is_deeply(
   $rows,
   [[8],[9],[10]],
   "--bulk-insert left 3 rows (issue 1260)"
);

$rows = $dbh->selectall_arrayref('select id from bri.t_arch order by id');
is_deeply(
   $rows,
   [[1],[2],[3],[4],[5],[6],[7]],
   "--bulk-insert archived 7 rows (issue 1260)"
);

# Test that the tool bails out early if LOAD DATA LOCAL INFILE is disabled
{
   if ( -d "/tmp/2900" ) {
      diag(`$trunk/sandbox/stop-sandbox 2900 >/dev/null 2>&1`);
   }

   local $ENV{LOCAL_INFILE} = 0;
   diag(`$trunk/sandbox/start-sandbox master 2900 >/dev/null 2>&1`);

   my $master3_dbh = $sb->get_dbh_for('master3');

   test_disabled_load_data($master3_dbh, $sb);

   diag(`$trunk/sandbox/stop-sandbox 2900 >/dev/null 2>&1`);
   $master3_dbh->disconnect() if $master3_dbh;
}

}

sub test_disabled_load_data {
   my ($dbh, $sb) = @_;
   $sb->wipe_clean($dbh);
   $sb->create_dbs($dbh, ['test']);
   $sb->load_file('master', 't/pt-archiver/samples/table5.sql');
   $dbh->do('INSERT INTO `test`.`table_5_copy` SELECT * FROM `test`.`table_5`');

   my ($output, undef) = full_output(
      sub { pt_archiver::main(qw(--no-ascend --limit 50 --bulk-insert),
         qw(--bulk-delete --where 1=1 --statistics),
         '--source', "D=test,t=table_5,F=$cnf",
         '--dest',   "t=table_5_dest") },
   );

   like($output,
      qr!\Q--bulk-insert cannot work as LOAD DATA LOCAL INFILE is disabled. See http://kb.percona.com/troubleshoot-load-data-infile!,
      "--bulk-insert throws an error if LOCAL INFILE is disabled"
   );
}

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
