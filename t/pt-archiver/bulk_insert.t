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

use charnames ':full';

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-archiver";

$sb->wipe_clean($dbh);
$sb->create_dbs($dbh, ['test']);

# Test --bulk-insert
$sb->load_file('master', 't/pt-archiver/samples/table5.sql');
$dbh->do('INSERT INTO `test`.`table_5_copy` SELECT * FROM `test`.`table_5`');

$output = output(
   sub { pt_archiver::main(qw(--no-ascend --limit 50 --bulk-insert),
      qw(--bulk-delete --where 1=1 --statistics),
      '--source', "L=1,D=test,t=table_5,F=$cnf",
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
my $orig_rows   = $dbh->selectall_arrayref('select id from bri.t order by id');
my $lt_8 = [ grep { $_->[0] < 8 } @$orig_rows ];
my $ge_8 = [ grep { $_->[0] >= 8 } @$orig_rows ];

$output = output(
   sub { pt_archiver::main(
       '--where', "id < 8", qw(--limit 100000 --txn-size 1000),
       qw(--why-quit --statistics --bulk-insert),
      '--source', "L=1,D=bri,t=t,F=$cnf",
      '--dest',   "t=t_arch") },
);
$rows = $dbh->selectall_arrayref('select id from bri.t order by id');
is_deeply(
   $rows,
   $ge_8,
   "--bulk-insert left 3 rows (issue 1260)"
);

$rows = $dbh->selectall_arrayref('select id from bri.t_arch order by id');
is_deeply(
   $rows,
   $lt_8,
   "--bulk-insert archived 7 rows (issue 1260)"
);

# #############################################################################
# pt-archiver wide character errors / corrupted data with UTF-8 + bulk-insert
# https://bugs.launchpad.net/percona-toolkit/+bug/1127450
# #############################################################################
if( Test::Builder->VERSION < 2 ) {
   foreach my $method ( qw(output failure_output) ) {
      binmode Test::More->builder->$method(), ':encoding(UTF-8)';
   }
}
# >"
for my $char ( "\N{KATAKANA LETTER NI}", "\N{U+DF}" ) {
   my $utf8_dbh = $sb->get_dbh_for('master', { mysql_enable_utf8 => 1, AutoCommit => 1 });

   $sb->load_file('master', 't/pt-archiver/samples/bug_1127450.sql');
   my $sql = qq{INSERT INTO `bug_1127450`.`original` VALUES (1, ?)};
   $utf8_dbh->prepare($sql)->execute($char);

   $output = output(
      sub { pt_archiver::main(qw(--no-ascend --limit 50 --bulk-insert),
         qw(--bulk-delete --where 1=1 --statistics --charset utf8),
         '--source', "L=1,D=bug_1127450,t=original,F=$cnf",
         '--dest',   "t=copy") }, stderr => 1
   );

   my (undef, $val) = $utf8_dbh->selectrow_array('select * from bug_1127450.copy');

   ok(
      $val,
      "--bulk-insert inserted the data"
   );

   utf8::decode($val);

   is(
      $val,
      $char,
      "--bulk-insert can handle $char"
   );

   unlike($output, qr/Wide character/, "no wide character warnings");

   my $test = $DBD::mysql::VERSION lt '4'
            ? \&like : \&unlike;
   $test->(
      $output,
      qr/Setting binmode :raw instead of :utf8 on/,
      "Warns about the UTF-8 bug in DBD::mysql::VERSION lt '4', quiet otherwise"
   );
}
# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
