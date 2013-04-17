#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use DSNParser;
use Sandbox;
use TableSyncNibble;
use Quoter;
use ChangeHandler;
use TableChecksum;
use TableChunker;
use TableNibbler;
use TableParser;
use VersionParser;
use MasterSlave;
use Retry;
use TableSyncer;
use PerconaTest;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 37;
}

my $mysql = $sb->_use_for('master');

my $q  = new Quoter();
my $ms = new MasterSlave(OptionParser=>1,DSNParser=>1,Quoter=>1);
my $tp = new TableParser(Quoter=>$q);
my $rr = new Retry();

my $nibbler = new TableNibbler(
   TableParser => $tp,
   Quoter      => $q,
);
my $checksum = new TableChecksum(
   Quoter        => $q,
);
my $chunker = new TableChunker(
   TableParser => $tp,
   Quoter      => $q
);
my $t = new TableSyncNibble(
   TableNibbler  => $nibbler,
   TableParser   => $tp,
   TableChunker  => $chunker,
   Quoter        => $q,
);

my @rows;
my $ch = new ChangeHandler(
   Quoter    => $q,
   right_db  => 'test',
   right_tbl => 'test1',
   left_db   => 'test',
   left_tbl  => 'test1',
   replace   => 0,
   actions   => [ sub { push @rows, $_[0] }, ],
   queue     => 0,
);

my $syncer = new TableSyncer(
   MasterSlave   => $ms,
   TableChecksum => $checksum,
   Quoter        => $q,
   Retry         => $rr,
);

$sb->create_dbs($dbh, ['test']);
diag(`$mysql < $trunk/t/lib/samples/before-TableSyncNibble.sql`);
my $ddl        = $tp->get_create_table($dbh, 'test', 'test1');
my $tbl_struct = $tp->parse($ddl);
my $src = {
   db  => 'test',
   tbl => 'test1',
   dbh => $dbh,
};
my $dst = {
   db  => 'test',
   tbl => 'test1',
   dbh => $dbh,
};
my %args       = (
   src           => $src,
   dst           => $dst,
   dbh           => $dbh,
   db            => 'test',
   tbl           => 'test1',
   tbl_struct    => $tbl_struct,
   cols          => $tbl_struct->{cols},
   chunk_size    => 1,
   chunk_index   => 'PRIMARY',
   key_cols      => $tbl_struct->{keys}->{PRIMARY}->{cols},
   crc_col       => '__crc',
   index_hint    => 'USE INDEX (`PRIMARY`)',
   ChangeHandler => $ch,
);

$t->prepare_to_sync(%args);
# Test with FNV_64 just to make sure there are no errors
eval { $dbh->do('select fnv_64(1)') };
SKIP: {
   skip 'No FNV_64 function installed', 1 if $EVAL_ERROR;

   $t->set_checksum_queries(
      $syncer->make_checksum_queries(%args, function => 'FNV_64')
   );
   is(
      $t->get_sql(
         database => 'test',
         table    => 'test1',
      ),
      q{SELECT /*test.test1:1/1*/ 0 AS chunk_num, COUNT(*) AS }
      . q{cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(FNV_64(`a`, `b`, `c`) AS UNSIGNED)), }
      . q{10, 16)), 0) AS crc FROM `test`.`test1` USE INDEX (`PRIMARY`) WHERE (((`a` < '1') OR (`a` = '1' }
      . q{AND `b` <= 'en')))},
      'First nibble SQL with FNV_64',
   );
}

$t->set_checksum_queries(
   $syncer->make_checksum_queries(%args, function => 'SHA1')
);
is(
   $t->get_sql(
      database => 'test',
      table    => 'test1',
   ),
   ($sandbox_version gt '4.0' ?
   q{SELECT /*test.test1:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONCAT(LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(@crc, 1, 16), 16, }
   . q{10) AS UNSIGNED)), 10, 16), 16, '0'), LPAD(CONV(BIT_XOR(CAST(CONV(}
   . q{SUBSTRING(@crc, 17, 16), 16, 10) AS UNSIGNED)), 10, 16), 16, '0'), }
   . q{LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(@crc := SHA1(CONCAT_WS('#', `a`, }
   . q{`b`, `c`)), 33, 8), 16, 10) AS UNSIGNED)), 10, 16), 8, '0'))), 0) AS crc FROM }
   . q{`test`.`test1` USE INDEX (`PRIMARY`) WHERE (((`a` < '1') OR (`a` = '1' AND `b` <= 'en')))} :
   q{SELECT /*test.test1:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, }
   . q{COALESCE(RIGHT(MAX(@crc := CONCAT(LPAD(@cnt := @cnt + 1, 16, '0'), }
   . q{SHA1(CONCAT(@crc, SHA1(CONCAT_WS('#', `a`, `b`, `c`)))))), 40), 0) AS crc FROM }
   . q{`test`.`test1` USE INDEX (`PRIMARY`) WHERE (((`a` < '1') OR (`a` = '1' AND `b` <= 'en')))}
   ),
   'First nibble SQL',
);

is(
   $t->get_sql(
      database => 'test',
      table    => 'test1',
   ),
   ($sandbox_version gt '4.0' ?
   q{SELECT /*test.test1:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONCAT(LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(@crc, 1, 16), 16, }
   . q{10) AS UNSIGNED)), 10, 16), 16, '0'), LPAD(CONV(BIT_XOR(CAST(CONV(}
   . q{SUBSTRING(@crc, 17, 16), 16, 10) AS UNSIGNED)), 10, 16), 16, '0'), }
   . q{LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(@crc := SHA1(CONCAT_WS('#', `a`, }
   . q{`b`, `c`)), 33, 8), 16, 10) AS UNSIGNED)), 10, 16), 8, '0'))), 0) AS crc FROM }
   . q{`test`.`test1` USE INDEX (`PRIMARY`) WHERE (((`a` < '1') OR (`a` = '1' AND `b` <= 'en')))} :
   q{SELECT /*test.test1:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, }
   . q{COALESCE(RIGHT(MAX(@crc := CONCAT(LPAD(@cnt := @cnt + 1, 16, '0'), }
   . q{SHA1(CONCAT(@crc, SHA1(CONCAT_WS('#', `a`, `b`, `c`)))))), 40), 0) AS crc FROM }
   . q{`test`.`test1` USE INDEX (`PRIMARY`) WHERE (((`a` < '1') OR (`a` = '1' AND `b` <= 'en')))}
   ),
   'First nibble SQL, again',
);

$t->{nibble} = 1;
delete $t->{cached_boundaries};

is(
   $t->get_sql(
      database => 'test',
      table    => 'test1',
   ),
   ($sandbox_version gt '4.0' ?
   q{SELECT /*test.test1:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONCAT(LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(@crc, 1, 16), 16, }
   . q{10) AS UNSIGNED)), 10, 16), 16, '0'), LPAD(CONV(BIT_XOR(CAST(CONV(}
   . q{SUBSTRING(@crc, 17, 16), 16, 10) AS UNSIGNED)), 10, 16), 16, '0'), }
   . q{LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(@crc := SHA1(CONCAT_WS('#', `a`, }
   . q{`b`, `c`)), 33, 8), 16, 10) AS UNSIGNED)), 10, 16), 8, '0'))), 0) AS crc FROM }
   . q{`test`.`test1` USE INDEX (`PRIMARY`) WHERE ((((`a` > '1') OR (`a` = '1' AND `b` > 'en')) AND }
   . q{((`a` < '2') OR (`a` = '2' AND `b` <= 'ca'))))} :
   q{SELECT /*test.test1:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, }
   . q{COALESCE(RIGHT(MAX(@crc := CONCAT(LPAD(@cnt := @cnt + 1, 16, '0'), }
   . q{SHA1(CONCAT(@crc, SHA1(CONCAT_WS('#', `a`, `b`, `c`)))))), 40), 0) AS crc FROM }
   . q{`test`.`test1` USE INDEX (`PRIMARY`) WHERE ((((`a` > '1') OR (`a` = '1' AND `b` > 'en')) AND }
   . q{((`a` < '2') OR (`a` = '2' AND `b` <= 'ca'))))}
   ),
   'Second nibble SQL',
);

# Bump the nibble boundaries ahead until we run off the end of the table.
$t->done_with_rows();
$t->get_sql(
      database => 'test',
      table    => 'test1',
   );
$t->done_with_rows();
$t->get_sql(
      database => 'test',
      table    => 'test1',
   );
$t->done_with_rows();
$t->get_sql(
      database => 'test',
      table    => 'test1',
   );

is(
   $t->get_sql(
      database => 'test',
      table    => 'test1',
   ),
   ($sandbox_version gt '4.0' ?
   q{SELECT /*test.test1:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONCAT(LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(@crc, 1, 16), 16, }
   . q{10) AS UNSIGNED)), 10, 16), 16, '0'), LPAD(CONV(BIT_XOR(CAST(CONV(}
   . q{SUBSTRING(@crc, 17, 16), 16, 10) AS UNSIGNED)), 10, 16), 16, '0'), }
   . q{LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(@crc := SHA1(CONCAT_WS('#', `a`, }
   . q{`b`, `c`)), 33, 8), 16, 10) AS UNSIGNED)), 10, 16), 8, '0'))), 0) AS crc FROM }
   . q{`test`.`test1` USE INDEX (`PRIMARY`) WHERE ((((`a` > '4') OR (`a` = '4' AND `b` > 'bz')) AND }
   . q{1=1))} :
   q{SELECT /*test.test1:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, }
   . q{COALESCE(RIGHT(MAX(@crc := CONCAT(LPAD(@cnt := @cnt + 1, 16, '0'), }
   . q{SHA1(CONCAT(@crc, SHA1(CONCAT_WS('#', `a`, `b`, `c`)))))), 40), 0) AS crc FROM }
   . q{`test`.`test1` USE INDEX (`PRIMARY`) WHERE ((((`a` > '4') OR (`a` = '4' AND `b` > 'bz')) AND }
   . q{1=1))}
   ),
   'End-of-table nibble SQL',
);

$t->done_with_rows();
ok($t->done(), 'Now done');

# Throw away and start anew, because it's off the end of the table
$t->{nibble} = 0;
delete $t->{cached_boundaries};
delete $t->{cached_nibble};
delete $t->{cached_row};

is_deeply($t->key_cols(), [qw(chunk_num)], 'Key cols in state 0');
$t->get_sql(
      database => 'test',
      table    => 'test1',
   );
$t->done_with_rows();

is($t->done(), '', 'Not done, because not reached end-of-table');

throws_ok(
   sub { $t->not_in_left() },
   qr/in state 0/,
   'not_in_(side) illegal in state 0',
);

# Now "find some bad chunks," as it were.

# "find a bad row"
$t->same_row(
   lr => { chunk_num => 0, cnt => 0, crc => 'abc' },
   rr => { chunk_num => 0, cnt => 1, crc => 'abc' },
);
ok($t->pending_changes(), 'Pending changes found');
is($t->{state}, 1, 'Working inside nibble');
$t->done_with_rows();
is($t->{state}, 2, 'Now in state to fetch individual rows');
ok($t->pending_changes(), 'Pending changes not done yet');
is($t->get_sql(database => 'test', table => 'test1'),
   q{SELECT /*rows in nibble*/ `a`, `b`, `c`, SHA1(CONCAT_WS('#', `a`, `b`, `c`)) AS __crc FROM }
   . q{`test`.`test1` USE INDEX (`PRIMARY`) WHERE ((((`a` > '1') OR (`a` = '1' AND `b` > 'en')) }
   . q{AND ((`a` < '2') OR (`a` = '2' AND `b` <= 'ca'))))}
   . q{ ORDER BY `a`, `b`},
   'SQL now working inside nibble'
);
ok($t->{state}, 'Still working inside nibble');
is(scalar(@rows), 0, 'No bad row triggered');

$t->not_in_left(rr => {a => 1, b => 'en'});

is_deeply(\@rows,
   ["DELETE FROM `test`.`test1` WHERE `a`='1' AND `b`='en' LIMIT 1"],
   'Working inside nibble, got a bad row',
);

# Shouldn't cause anything to happen
$t->same_row(
   lr => {a => 1, b => 'en', __crc => 'foo'},
   rr => {a => 1, b => 'en', __crc => 'foo'} );

is_deeply(\@rows,
   ["DELETE FROM `test`.`test1` WHERE `a`='1' AND `b`='en' LIMIT 1"],
   'No more rows added',
);

$t->same_row(
   lr => {a => 1, b => 'en', __crc => 'foo'},
   rr => {a => 1, b => 'en', __crc => 'bar'} );

is_deeply(\@rows,
   [
      "DELETE FROM `test`.`test1` WHERE `a`='1' AND `b`='en' LIMIT 1",
      "UPDATE `test`.`test1` SET `c`='a' WHERE `a`='1' AND `b`='en' LIMIT 1",
   ],
   'Row added to update differing row',
);

$t->done_with_rows();
is($t->{state}, 0, 'Now not working inside nibble');
is($t->pending_changes(), 0, 'No pending changes');

# Now test that SQL_BUFFER_RESULT is in the queries OK
$t->prepare_to_sync(%args, buffer_in_mysql=>1);
$t->{state} = 1;
like(
   $t->get_sql(
      database => 'test',
      table    => 'test1',
      buffer_in_mysql => 1,
   ),
   qr/SELECT ..rows in nibble.. SQL_BUFFER_RESULT/,
   'Buffering in first nibble',
);

# "find a bad row"
$t->same_row(
   lr => { chunk_num => 0, cnt => 0, __crc => 'abc' },
   rr => { chunk_num => 0, cnt => 1, __crc => 'abc' },
);

like(
   $t->get_sql(
      database => 'test',
      table    => 'test1',
      buffer_in_mysql => 1,
   ),
   qr/SELECT ..rows in nibble.. SQL_BUFFER_RESULT/,
   'Buffering in next nibble',
);

# #########################################################################
# Issue 96: mk-table-sync: Nibbler infinite loop
# #########################################################################
$sb->load_file('master', 't/lib/samples/issue_96.sql');
$tbl_struct = $tp->parse($tp->get_create_table($dbh, 'issue_96', 't'));
$t->prepare_to_sync(
   ChangeHandler  => $ch,
   cols           => $tbl_struct->{cols},
   dbh            => $dbh,
   db             => 'issue_96',
   tbl            => 't',
   tbl_struct     => $tbl_struct,
   chunk_size     => 2,
   chunk_index    => 'package_id',
   crc_col        => '__crc_col',
   index_hint     => 'FORCE INDEX(`package_id`)',
   key_cols       => $tbl_struct->{keys}->{package_id}->{cols},
);

# Test that we die if MySQL isn't using the chosen index (package_id)
# for the boundary sql.

my $sql = "SELECT /*nibble boundary 0*/ `package_id`,`location`,`from_city` FROM `issue_96`.`t` FORCE INDEX(`package_id`) ORDER BY `package_id`,`location` LIMIT 1, 1";
is(
   $t->__get_explain_index($sql),
   'package_id',
   '__get_explain_index()'
);

diag(`/tmp/12345/use -e 'ALTER TABLE issue_96.t DROP INDEX package_id'`);

is(
   $t->__get_explain_index($sql),
   undef,
   '__get_explain_index() for nonexistent index'
);

my %args2 = ( database=>'issue_96', table=>'t' );
eval {
   $t->get_sql(database=>'issue_96', tbl=>'t', %args2);
};
like(
   $EVAL_ERROR,
   qr/^Cannot nibble table `issue_96`.`t` because MySQL chose no index instead of the `package_id` index/,
   "Die if MySQL doesn't choose our index (issue 96)"
);

# Restore the index, get the first sql boundary and check that it
# has the proper ORDER BY clause which makes MySQL use the index.
diag(`/tmp/12345/use -e 'ALTER TABLE issue_96.t ADD UNIQUE INDEX package_id (package_id,location);'`);
eval {
   ($sql,undef) = $t->__make_boundary_sql(%args2);
};
is(
   $sql,
   "SELECT /*nibble boundary 0*/ `package_id`,`location`,`from_city` FROM `issue_96`.`t` FORCE INDEX(`package_id`) ORDER BY `package_id`,`location` LIMIT 1, 1",
   'Boundary SQL has ORDER BY key columns'
);

# If small_table is true, the index check should be skipped.
diag(`/tmp/12345/use -e 'create table issue_96.t3 (i int, unique index (i))'`);
diag(`/tmp/12345/use -e 'insert into issue_96.t3 values (1)'`);
$tbl_struct = $tp->parse($tp->get_create_table($dbh, 'issue_96', 't3'));
$t->prepare_to_sync(
   ChangeHandler  => $ch,
   cols           => $tbl_struct->{cols},
   dbh            => $dbh,
   db             => 'issue_96',
   tbl            => 't3',
   tbl_struct     => $tbl_struct,
   chunk_size     => 2,
   chunk_index    => 'i',
   crc_col        => '__crc_col',
   index_hint     => 'FORCE INDEX(`i`)',
   key_cols       => $tbl_struct->{keys}->{i}->{cols},
   small_table    => 1,
);
eval {
   $t->get_sql(database=>'issue_96', table=>'t3');
};
is(
   $EVAL_ERROR,
   '',
   "Skips index check when small table (issue 634)"
);

my ($can_sync, %plugin_args);
SKIP: {
   skip "Not tested on MySQL $sandbox_version", 5
      unless $sandbox_version gt '4.0';

# #############################################################################
# Issue 560: mk-table-sync generates impossible WHERE
# Issue 996: might not chunk inside of mk-table-checksum's boundaries
# #############################################################################
# Due to issue 996 this test has changed.  Now it *should* use the replicate
# boundary provided via the where arg and nibble just inside this boundary.
# If it does, then it will prevent the impossible WHERE of issue 560.

# The buddy_list table has 500 rows, so when it's chunk into 100 rows this is
# chunk 2:
my $where = '`player_id` >= 201 AND `player_id` < 301';

$sb->load_file('master', 't/pt-table-sync/samples/issue_560.sql');
$tbl_struct = $tp->parse($tp->get_create_table($dbh, 'issue_560', 'buddy_list'));
(undef, %plugin_args) = $t->can_sync(tbl_struct => $tbl_struct);
$t->prepare_to_sync(
   ChangeHandler  => $ch,
   cols           => $tbl_struct->{cols},
   dbh            => $dbh,
   db             => 'issue_560',
   tbl            => 'buddy_list',
   tbl_struct     => $tbl_struct,
   chunk_size     => 100,
   crc_col        => '__crc_col',
   %plugin_args,
   replicate      => 'issue_560.checksum',
   where          => $where,  # not used in sub but normally passed so we
                              # do the same to simulate a real run
);

# Must call this else $row_sql will have values from previous test.
$t->set_checksum_queries(
   $syncer->make_checksum_queries(
      src        => $src,
      dst        => $dst,
      tbl_struct => $tbl_struct,
   )
);

is(
   $t->get_sql(
      where    => $where,
      database => 'issue_560',
      table    => 'buddy_list', 
   ),
   "SELECT /*issue_560.buddy_list:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `player_id`, `buddy_id`)) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_560`.`buddy_list`  WHERE (((`player_id` < '300') OR (`player_id` = '300' AND `buddy_id` <= '2085'))) AND (($where))",
   'Nibble with chunk boundary (chunk sql)'
);

$t->{state} = 2;
is(
   $t->get_sql(
      where    => $where,
      database => 'issue_560',
      table    => 'buddy_list', 
   ),
   "SELECT /*rows in nibble*/ `player_id`, `buddy_id`, CRC32(CONCAT_WS('#', `player_id`, `buddy_id`)) AS __crc_col FROM `issue_560`.`buddy_list`  WHERE (((`player_id` < '300') OR (`player_id` = '300' AND `buddy_id` <= '2085'))) AND ($where) ORDER BY `player_id`, `buddy_id`",
   'Nibble with chunk boundary (row sql)'
);

$t->{state} = 0;
$t->done_with_rows();
is(
   $t->get_sql(
      where    => $where,
      database => 'issue_560',
      table    => 'buddy_list', 
   ),
   "SELECT /*issue_560.buddy_list:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `player_id`, `buddy_id`)) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_560`.`buddy_list`  WHERE ((((`player_id` > '300') OR (`player_id` = '300' AND `buddy_id` > '2085')) AND 1=1)) AND (($where))",
   "Next sub-nibble",
);

# Just like the previous tests but this time the chunk size is 50 so we
# should nibble two chunks within the larger range ($where).
$t->prepare_to_sync(
   ChangeHandler  => $ch,
   cols           => $tbl_struct->{cols},
   dbh            => $dbh,
   db             => 'issue_560',
   tbl            => 'buddy_list',
   tbl_struct     => $tbl_struct,
   chunk_size     => 50,              # 2 sub-nibbles
   crc_col        => '__crc_col',
   %plugin_args,
   replicate      => 'issue_560.checksum',
   where          => $where,  # not used in sub but normally passed so we
                              # do the same to simulate a real run
);

# Must call this else $row_sql will have values from previous test.
$t->set_checksum_queries(
   $syncer->make_checksum_queries(
      src        => $src,
      dst        => $dst,
      tbl_struct => $tbl_struct,
   )
);

is(
   $t->get_sql(
      where    => $where,
      database => 'issue_560',
      table    => 'buddy_list', 
   ),
   "SELECT /*issue_560.buddy_list:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `player_id`, `buddy_id`)) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_560`.`buddy_list`  WHERE (((`player_id` < '250') OR (`player_id` = '250' AND `buddy_id` <= '809'))) AND ((`player_id` >= 201 AND `player_id` < 301))",
   "Sub-nibble 1"
);

$t->done_with_rows();
is(
   $t->get_sql(
      where    => $where,
      database => 'issue_560',
      table    => 'buddy_list', 
   ),
   "SELECT /*issue_560.buddy_list:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `player_id`, `buddy_id`)) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_560`.`buddy_list`  WHERE ((((`player_id` > '250') OR (`player_id` = '250' AND `buddy_id` > '809')) AND ((`player_id` < '300') OR (`player_id` = '300' AND `buddy_id` <= '2085')))) AND ((`player_id` >= 201 AND `player_id` < 301))",
   "Sub-nibble 2"
);
}

# #############################################################################
# Issue 804: mk-table-sync: can't nibble because index name isn't lower case?
# #############################################################################
$sb->load_file('master', 't/lib/samples/issue_804.sql');
$tbl_struct = $tp->parse($tp->get_create_table($dbh, 'issue_804', 't'));
($can_sync, %plugin_args) = $t->can_sync(tbl_struct => $tbl_struct);
is(
   $can_sync,
   1,
   'Can sync issue_804 table'
);
is_deeply(
   \%plugin_args,
   {
      chunk_index => 'purchases_accountid_purchaseid',
      key_cols    => [qw(accountid purchaseid)],
      small_table => 0,
   },
   'Plugin args for issue_804 table'
);

$t->prepare_to_sync(
   ChangeHandler  => $ch,
   cols           => $tbl_struct->{cols},
   dbh            => $dbh,
   db             => 'issue_804',
   tbl            => 't',
   tbl_struct     => $tbl_struct,
   chunk_size     => 50,
   chunk_index    => $plugin_args{chunk_index},
   crc_col        => '__crc_col',
   index_hint     => 'FORCE INDEX(`'.$plugin_args{chunk_index}.'`)',
   key_cols       => $tbl_struct->{keys}->{$plugin_args{chunk_index}}->{cols},
);

# Must call this else $row_sql will have values from previous test.
$t->set_checksum_queries(
   $syncer->make_checksum_queries(
      src        => $src,
      dst        => $dst,
      tbl_struct => $tbl_struct,
   )
);

# Before fixing issue 804, the code would die during this call, saying:
# Cannot nibble table `issue_804`.`t` because MySQL chose the
# `purchases_accountId_purchaseId` index instead of the
# `purchases_accountid_purchaseid` index at TableSyncNibble.pm line 284.
$sql = $t->get_sql(database=>'issue_804', table=>'t');
is(
   $sql,
   ($sandbox_version gt '4.0' ?
   "SELECT /*issue_804.t:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `accountid`, `purchaseid`)) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_804`.`t` FORCE INDEX(`purchases_accountid_purchaseid`) WHERE (((`accountid` < '49') OR (`accountid` = '49' AND `purchaseid` <= '50')))" :
   "SELECT /*issue_804.t:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, COALESCE(RIGHT(MAX(\@crc := CONCAT(LPAD(\@cnt := \@cnt + 1, 16, '0'), MD5(CONCAT(\@crc, MD5(CONCAT_WS('#', `accountid`, `purchaseid`)))))), 32), 0) AS crc FROM `issue_804`.`t` FORCE INDEX(`purchases_accountid_purchaseid`) WHERE (((`accountid` < '49') OR (`accountid` = '49' AND `purchaseid` <= '50')))"
   ),
   'SQL nibble for issue_804 table'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
