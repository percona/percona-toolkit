#!/usr/bin/perl

BEGIN {
   die
      "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
}

use strict;
use warnings FATAL => 'all';

use Test::More;
use English qw(-no_match_vars);

use QueryRewriter;
use QueryParser;
use PerconaTest;

my $qp = new QueryParser;
my $qr = new QueryRewriter( QueryParser => $qp );

isa_ok( $qp, 'QueryParser' );

# A subroutine to make tests easy to write.
sub test_query {
   my ( $query, $aliases, $tables, $msg, %args ) = @_;
   is_deeply(
      $qp->get_aliases( $query, $args{list} ),
      $aliases, "get_aliases: $msg",
   );
   is_deeply( [ $qp->get_tables($query) ], $tables, "get_tables:  $msg", );
   return;
}

# #############################################################################
# Misc stuff.
# #############################################################################
is( $qp->trim_identifier('`foo` '), 'foo', 'Trim backticks and spaces' );
is( $qp->trim_identifier(' `db`.`t1`'),
   'db.t1', 'Trim more backticks and spaces' );

# #############################################################################
# All manner of "normal" SELECT queries.
# #############################################################################

# 1 table
test_query(
   'SELECT * FROM t1 WHERE id = 1',
   {  DATABASE => {},
      TABLE    => { 't1' => 't1', },
   },
   [qw(t1)],
   'one table no alias'
);

test_query(
   'SELECT * FROM t1 a WHERE id = 1',
   {  DATABASE => {},
      TABLE    => { 'a' => 't1', },
   },
   [qw(t1)],
   'one table implicit alias'
);

test_query(
   'SELECT * FROM t1 AS a WHERE id = 1',
   {  DATABASE => {},
      TABLE    => { 'a' => 't1', }
   },
   [qw(t1)],
   'one table AS alias'
);

test_query(
   'SELECT * FROM t1',
   {  DATABASE => {},
      TABLE    => { t1 => 't1', }
   },
   [qw(t1)],
   'one table no alias and no following clauses',
);

# 2 tables
test_query(
   'SELECT * FROM t1, t2 WHERE id = 1',
   {  DATABASE => {},
      TABLE    => {
         't1' => 't1',
         't2' => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables no aliases'
);

test_query(
   'SELECT * FROM t1 a, t2 WHERE foo = "bar"',
   {  DATABASE => {},
      TABLE    => {
         a  => 't1',
         t2 => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables implicit alias and no alias',
);

test_query(
   'SELECT * FROM t1 a, t2 b WHERE id = 1',
   {  DATABASE => {},
      TABLE    => {
         'a' => 't1',
         'b' => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables implicit aliases'
);

test_query(
   'SELECT * FROM t1 AS a, t2 AS b WHERE id = 1',
   {  DATABASE => {},
      TABLE    => {
         'a' => 't1',
         'b' => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables AS aliases'
);

test_query(
   'SELECT * FROM t1 AS a, t2 b WHERE id = 1',
   {  DATABASE => {},
      TABLE    => {
         'a' => 't1',
         'b' => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables AS alias and implicit alias'
);

test_query(
   'SELECT * FROM t1 a, t2 AS b WHERE id = 1',
   {  DATABASE => {},
      TABLE    => {
         'a' => 't1',
         'b' => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables implicit alias and AS alias'
);

test_query(
   'SELECT * FROM t1 a, t2 AS b WHERE id = 1',
   [ 't1 a', 't2 AS b', ],
   [qw(t1 t2)],
   'two tables implicit alias and AS alias, with alias',
   list => 1,
);

# ANSI JOINs
test_query(
   'SELECT * FROM t1 JOIN t2 ON a.id = b.id',
   {  DATABASE => {},
      TABLE    => {
         't1' => 't1',
         't2' => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables no aliases JOIN'
);

test_query(
   'SELECT * FROM t1 a JOIN t2 b ON a.id = b.id',
   {  DATABASE => {},
      TABLE    => {
         'a' => 't1',
         'b' => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables implicit aliases JOIN'
);

test_query(
   'SELECT * FROM t1 AS a JOIN t2 as b ON a.id = b.id',
   {  DATABASE => {},
      TABLE    => {
         'a' => 't1',
         'b' => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables AS aliases JOIN'
);

test_query(
   'SELECT * FROM t1 AS a JOIN t2 b ON a.id=b.id WHERE id = 1',
   {  DATABASE => {},
      TABLE    => {
         a => 't1',
         b => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables AS alias and implicit alias JOIN'
);

test_query(
   'SELECT * FROM t1 LEFT JOIN t2 ON a.id = b.id',
   {  DATABASE => {},
      TABLE    => {
         't1' => 't1',
         't2' => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables no aliases LEFT JOIN'
);

test_query(
   'SELECT * FROM t1 a LEFT JOIN t2 b ON a.id = b.id',
   {  DATABASE => {},
      TABLE    => {
         'a' => 't1',
         'b' => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables implicit aliases LEFT JOIN'
);

test_query(
   'SELECT * FROM t1 AS a LEFT JOIN t2 as b ON a.id = b.id',
   {  DATABASE => {},
      TABLE    => {
         'a' => 't1',
         'b' => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables AS aliases LEFT JOIN'
);

test_query(
   'SELECT * FROM t1 AS a LEFT JOIN t2 b ON a.id=b.id WHERE id = 1',
   {  DATABASE => {},
      TABLE    => {
         a => 't1',
         b => 't2',
      },
   },
   [qw(t1 t2)],
   'two tables AS alias and implicit alias LEFT JOIN'
);

# 3 tables
test_query(
   'SELECT * FROM t1 JOIN t2 ON t1.col1=t2.col2 JOIN t3 ON t2.col3 = t3.col4 WHERE foo = "bar"',
   {  DATABASE => {},
      TABLE    => {
         t1 => 't1',
         t2 => 't2',
         t3 => 't3',
      },
   },
   [qw(t1 t2 t3)],
   'three tables no aliases JOIN'
);

test_query(
   'SELECT * FROM t1 AS a, t2, t3 c WHERE id = 1',
   {  DATABASE => {},
      TABLE    => {
         a  => 't1',
         t2 => 't2',
         c  => 't3',
      },
   },
   [qw(t1 t2 t3)],
   'three tables AS alias, no alias, implicit alias'
);

test_query(
   'SELECT * FROM t1 a, t2 b, t3 c WHERE id = 1',
   {  DATABASE => {},
      TABLE    => {
         a => 't1',
         b => 't2',
         c => 't3',
      },
   },
   [qw(t1 t2 t3)],
   'three tables implicit aliases'
);

# Db-qualified tables
test_query(
   'SELECT * FROM db.t1 AS a WHERE id = 1',
   {  TABLE      => { 'a'  => 't1', },
      'DATABASE' => { 't1' => 'db', },
   },
   [qw(db.t1)],
   'one db-qualified table AS alias'
);

test_query(
   'SELECT * FROM `db`.`t1` AS a WHERE id = 1',
   {  TABLE      => { 'a'  => 't1', },
      'DATABASE' => { 't1' => 'db', },
   },
   [qw(`db`.`t1`)],
   'one db-qualified table AS alias with backticks'
);

# Other cases
test_query(
   q{SELECT a FROM store_orders_line_items JOIN store_orders},
   {  DATABASE => {},
      TABLE    => {
         store_orders_line_items => 'store_orders_line_items',
         store_orders            => 'store_orders',
      },
   },
   [qw(store_orders_line_items store_orders)],
   'Embedded ORDER keyword',
);

# #############################################################################
# Non-SELECT queries.
# #############################################################################
test_query(
   'UPDATE foo AS bar SET value = 1 WHERE 1',
   {  DATABASE => {},
      TABLE    => { bar => 'foo', },
   },
   [qw(foo)],
   'update with one AS alias',
);

test_query(
   'UPDATE IGNORE foo bar SET value = 1 WHERE 1',
   {  DATABASE => {},
      TABLE    => { bar => 'foo', },
   },
   [qw(foo)],
   'update ignore with one implicit alias',
);

test_query(
   'UPDATE IGNORE bar SET value = 1 WHERE 1',
   {  DATABASE => {},
      TABLE    => { bar => 'bar', },
   },
   [qw(bar)],
   'update ignore with one not aliased',
);

test_query(
   'UPDATE LOW_PRIORITY baz SET value = 1 WHERE 1',
   {  DATABASE => {},
      TABLE    => { baz => 'baz', },
   },
   [qw(baz)],
   'update low_priority with one not aliased',
);

test_query(
   'UPDATE LOW_PRIORITY IGNORE bat SET value = 1 WHERE 1',
   {  DATABASE => {},
      TABLE    => { bat => 'bat', },
   },
   [qw(bat)],
   'update low_priority ignore with one not aliased',
);

test_query(
   'INSERT INTO foo VALUES (1)',
   {  DATABASE => {},
      TABLE    => { foo => 'foo', }
   },
   [qw(foo)],
   'insert with one not aliased',
);

test_query(
   'INSERT INTO foo VALUES (1) ON DUPLICATE KEY UPDATE bar = 1',
   {  DATABASE => {},
      TABLE    => { foo => 'foo', },
   },
   [qw(foo)],
   'insert / on duplicate key update',
);

# #############################################################################
# Non-DMS queries.
# #############################################################################
test_query(
   'BEGIN',
   {  DATABASE => {},
      TABLE    => {},
   },
   [],
   'BEGIN'
);

# #############################################################################
# Diabolical dbs and tbls with spaces in their names.
# #############################################################################

test_query(
   'select * from `my table` limit 1;',
   {  DATABASE => {},
      TABLE    => { 'my table' => 'my table', }
   },
   ['`my table`'],
   'one table with space in name, not aliased',
);

test_query(
   'select * from `my database`.mytable limit 1;',
   {  TABLE    => { mytable => 'mytable', },
      DATABASE => { mytable => 'my database', },
   },
   ['`my database`.mytable'],
   'one db.tbl with space in db, not aliased',
);

test_query(
   'select * from `my database`.`my table` limit 1; ',
   {  TABLE    => { 'my table' => 'my table', },
      DATABASE => { 'my table' => 'my database', },
   },
   ['`my database`.`my table`'],
   'one db.tbl with space in both db and tbl, not aliased',
);

# #############################################################################
# Issue 185: QueryParser fails to parse table ref for a JOIN ... USING
# #############################################################################
test_query(
   'select  n.column1 = a.column1, n.word3 = a.word3 from db2.tuningdetail_21_265507 n inner join db1.gonzo a using(gonzo)',
   {  TABLE => {
         'n' => 'tuningdetail_21_265507',
         'a' => 'gonzo',
      },
      'DATABASE' => {
         'tuningdetail_21_265507' => 'db2',
         'gonzo'                  => 'db1',
      },
   },
   [qw(db2.tuningdetail_21_265507 db1.gonzo)],
   'SELECT with JOIN ON and no WHERE (issue 185)'
);

# #############################################################################
test_query(
   'select 12_13_foo from (select 12foo from 123_bar) as 123baz',
   {  DATABASE => {},
      TABLE    => { '123baz' => undef, },
   },
   [qw(123_bar)],
   'Subquery in the FROM clause'
);

test_query(
   q{UPDATE GARDEN_CLUPL PL, GARDENJOB GC, APLTRACT_GARDENPLANT ABU SET }
      . q{GC.MATCHING_POT = 5, GC.LAST_GARDENPOT = 5, GC.LAST_NAME=}
      . q{'Rotary', GC.LAST_BUCKET='Pail', GC.LAST_UPDATE='2008-11-27 04:00:59'WHERE}
      . q{ PL.APLTRACT_GARDENPLANT_ID = GC.APLTRACT_GARDENPLANT_ID AND PL.}
      . q{APLTRACT_GARDENPLANT_ID = ABU.ID AND GC.MATCHING_POT = 0 AND GC.PERFORM_DIG=1}
      . q{ AND ABU.DIG = 6 AND ( ((SOIL-COST) > -80.0}
      . q{ AND BUGS < 60.0 AND (SOIL-COST) < 200.0) AND POTS < 10.0 )},
   {  DATABASE => {},
      TABLE    => {
         PL  => 'GARDEN_CLUPL',
         GC  => 'GARDENJOB',
         ABU => 'APLTRACT_GARDENPLANT',
      },
   },
   [qw(GARDEN_CLUPL GARDENJOB APLTRACT_GARDENPLANT)],
   'Gets tables from query with aliases and comma-join',
);

test_query(
   q{SELECT count(*) AS count_all FROM `impact_actions`  LEFT OUTER JOIN }
      . q{recommended_change_events ON (impact_actions.event_id = }
      . q{recommended_change_events.event_id) LEFT OUTER JOIN }
      . q{recommended_change_aments ON (impact_actions.ament_id = }
      . q{recommended_change_aments.ament_id) WHERE (impact_actions.user_id = 71058 }

      # An old version of the regex used to think , was the precursor to a
      # table name, so it would pull out 7,8,9,10,11 as table names.
      . q{AND (impact_actions.action_type IN (4,7,8,9,10,11) AND }
      . q{(impact_actions.change_id = 2699 OR recommended_change_events.change_id = }
      . q{2699 OR recommended_change_aments.change_id = 2699)))},
   {  DATABASE => {},
      TABLE    => {
         'impact_actions'            => 'impact_actions',
         'recommended_change_events' => 'recommended_change_events',
         'recommended_change_aments' => 'recommended_change_aments',
      },
   },
   [qw(`impact_actions` recommended_change_events recommended_change_aments)],
   'Does not think IN() list has table names',
);

test_query(
   'INSERT INTO my.tbl VALUES("I got this FROM the newspaper today")',
   {  TABLE    => { 'tbl' => 'tbl', },
      DATABASE => { 'tbl' => 'my' },
   },
   [qw(my.tbl)],
   'Not confused by quoted string'
);

is_deeply(
   [  $qp->get_tables(
              q{REPLACE /*foo.bar:3/3*/ INTO checksum.checksum (db, tbl, }
            . q{chunk, boundaries, this_cnt, this_crc) SELECT 'foo', 'bar', }
            . q{2 AS chunk_num, '`id` >= 2166633', COUNT(*) AS cnt, }
            . q{LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `id`, `created_by`, }
            . q{`created_date`, `updated_by`, `updated_date`, `ppc_provider`, }
            . q{`account_name`, `provider_account_id`, `campaign_name`, }
            . q{`provider_campaign_id`, `adgroup_name`, `provider_adgroup_id`, }
            . q{`provider_keyword_id`, `provider_ad_id`, `foo`, `reason`, }
            . q{`foo_bar_bazz_id`, `foo_bar_baz`, CONCAT(ISNULL(`created_by`), }
            . q{ISNULL(`created_date`), ISNULL(`updated_by`), ISNULL(`updated_date`), }
            . q{ISNULL(`ppc_provider`), ISNULL(`account_name`), }
            . q{ISNULL(`provider_account_id`), ISNULL(`campaign_name`), }
            . q{ISNULL(`provider_campaign_id`), ISNULL(`adgroup_name`), }
            . q{ISNULL(`provider_adgroup_id`), ISNULL(`provider_keyword_id`), }
            . q{ISNULL(`provider_ad_id`), ISNULL(`foo`), ISNULL(`reason`), }
            . q{ISNULL(`foo_base_foo_id`), ISNULL(`fooe_foo_id`)))) AS UNSIGNED)), 10, }
            . q{16)) AS crc FROM `foo`.`bar` USE INDEX (`PRIMARY`) WHERE }
            . q{(`id` >= 2166633); }
      )
   ],
   [qw(checksum.checksum `foo`.`bar`)],
   'gets tables from nasty checksum query',
);

is_deeply(
   [  $qp->get_tables(q{SELECT STRAIGHT_JOIN distinct foo, bar FROM A, B, C})
   ],
   [qw(A B C)],
   'gets tables from STRAIGHT_JOIN',
);

is_deeply(
   [  $qp->get_tables(
         'replace into checksum.checksum select `last_update`, `foo` from foo.foo'
      )
   ],
   [qw(checksum.checksum foo.foo)],
   'gets tables with reserved words'
);

is_deeply(
   [  $qp->get_tables(
         'SELECT * FROM (SELECT * FROM foo WHERE UserId = 577854809 ORDER BY foo DESC) q1 GROUP BY foo ORDER BY bar DESC LIMIT 3'
      )
   ],
   [qw(foo)],
   'get_tables on simple subquery'
);

is_deeply(
   [  $qp->get_tables(
         'INSERT INTO my.tbl VALUES("I got this from the newspaper")')
   ],
   [qw(my.tbl)],
   'Not confused by quoted string'
);

is_deeply( [ $qp->get_tables('create table db.tbl (i int)') ],
   [qw(db.tbl)], 'get_tables: CREATE TABLE' );

is_deeply( [ $qp->get_tables('create TEMPORARY table db.tbl2 (i int)') ],
   [qw(db.tbl2)], 'get_tables: CREATE TEMPORARY TABLE' );

is_deeply( [ $qp->get_tables('create table if not exists db.tbl (i int)') ],
   [qw(db.tbl)], 'get_tables: CREATE TABLE IF NOT EXISTS' );

is_deeply(
   [  $qp->get_tables('create TEMPORARY table IF NOT EXISTS db.tbl3 (i int)')
   ],
   [qw(db.tbl3)],
   'get_tables: CREATE TEMPORARY TABLE IF NOT EXISTS'
);

is_deeply(
   [  $qp->get_tables(
         'CREATE TEMPORARY TABLE `foo` AS select * from bar where id = 1')
   ],
   [qw(bar)],
   'get_tables: CREATE TABLE ... SELECT'
);

is_deeply( [ $qp->get_tables('ALTER TABLE db.tbl ADD COLUMN (j int)') ],
   [qw(db.tbl)], 'get_tables: ALTER TABLE' );

is_deeply( [ $qp->get_tables('DROP TABLE db.tbl') ],
   [qw(db.tbl)], 'get_tables: DROP TABLE' );

is_deeply( [ $qp->get_tables('truncate table db.tbl') ],
   [qw(db.tbl)], 'get_tables: TRUNCATE TABLE' );

is_deeply( [ $qp->get_tables('create database foo') ],
   [], 'get_tables: CREATE DATABASE (no tables)' );

is_deeply(
   [  $qp->get_tables(
         'INSERT INTO `foo` (`s`,`from`,`t`,`p`) VALVUES ("not","me","foo",1)'
      )
   ],
   [qw(`foo`)],
   'Throws out suspicious table names'
);

ok( $qp->has_derived_table('select * from ( select 1) as x'),
   'simple derived' );
ok( $qp->has_derived_table('select * from a join ( select 1) as x'),
   'join, derived' );
ok( $qp->has_derived_table('select * from a join b, (select 1) as x'),
   'comma join, derived' );
is( $qp->has_derived_table('select * from foo'), '', 'no derived' );
is( $qp->has_derived_table('select * from foo where a in(select a from b)'),
   '', 'no derived on correlated' );

# #############################################################################
# Test split().
# #############################################################################
is_deeply(
   [ $qp->split('SELECT * FROM db.tbl WHERE id = 1') ],
   [ 'SELECT * FROM db.tbl WHERE id = 1', ],
   'split 1 statement, SELECT'
);

my $sql
   = 'replace into db1.tbl2 (dt, hr) select foo, bar from db2.tbl2 where id = 1 group by foo';
is_deeply(
   [ $qp->split($sql) ],
   [  'replace into db1.tbl2 (dt, hr) ',
      'select foo, bar from db2.tbl2 where id = 1 group by foo',
   ],
   'split 2 statements, REPLACE ... SELECT'
);

$sql
   = 'insert into db1.tbl 1 (dt,hr) select dt,hr from db2.tbl2 where foo = 1';
is_deeply(
   [ $qp->split($sql) ],
   [  'insert into db1.tbl 1 (dt,hr) ',
      'select dt,hr from db2.tbl2 where foo = 1',
   ],
   'split 2 statements, INSERT ... SELECT'
);

$sql
   = 'create table if not exists db.tbl (primary key (lmp), id int not null unique key auto_increment, lmp datetime)';
is_deeply( [ $qp->split($sql) ], [ $sql, ], 'split 1 statement, CREATE' );

$sql = "select num from db.tbl where replace(col,' ','') = 'foo'";
is_deeply( [ $qp->split($sql) ],
   [ $sql, ], 'split 1 statement, SELECT with REPLACE() function' );

$sql = "
               INSERT INTO db.tbl (i, t, c, m) VALUES (237527, '', 0, '1 rows')";
is_deeply(
   [ $qp->split($sql) ],
   [ "INSERT INTO db.tbl (i, t, c, m) VALUES (237527, '', 0, '1 rows')", ],
   'split 1 statement, INSERT with leading newline and spaces'
);

$sql = 'create table db1.tbl1 SELECT id FROM db2.tbl2 WHERE time = 46881;';
is_deeply(
   [ $qp->split($sql) ],
   [  'create table db1.tbl1 ',
      'SELECT id FROM db2.tbl2 WHERE time = 46881;',
   ],
   'split 2 statements, CREATE ... SELECT'
);

$sql
   = "/*<font color = 'blue'>MAIN FUNCTION </font><br>*/                 insert into p.b317  (foo) select p.b1927.rtb as pr   /* inner join  pa7.r on pr.pd = c.pd */            inner join m.da on da.hr=p.hr and  da.node=pr.node     ;";
is_deeply(
   [ $qp->split($sql) ],
   [  'insert into p.b317 (foo) ',
      'select p.b1927.rtb as pr inner join m.da on da.hr=p.hr and da.node=pr.node ;',
   ],
   'split statements with comment blocks'
);

$sql
   = "insert into test1.tbl6 (day) values ('monday') on duplicate key update metric11 = metric11 + 1";
is_deeply( [ $qp->split($sql) ], [ $sql, ], 'split "on duplicate key"' );

# #############################################################################
# Test split_subquery().
# #############################################################################
$sql = 'SELECT * FROM t1 WHERE column1 = (SELECT column1 FROM t2);';
is_deeply(
   [ $qp->split_subquery($sql) ],
   [  'SELECT * FROM t1 WHERE column1 = (__subquery_1)',
      '(SELECT column1 FROM t2)',
   ],
   'split_subquery() basic'
);

# #############################################################################
# Test query_type().
# #############################################################################
is_deeply(
   $qp->query_type( 'select * from foo where id=1', $qr ),
   {  type => 'SELECT',
      rw   => 'read',
   },
   'query_type() select'
);
is_deeply(
   $qp->query_type( '/* haha! */ select * from foo where id=1', $qr ),
   {  type => 'SELECT',
      rw   => 'read',
   },
   'query_type() select with leading /* comment */'
);
is_deeply(
   $qp->query_type( 'insert into foo values (1, 2)', $qr ),
   {  type => 'INSERT',
      rw   => 'write',
   },
   'query_type() insert'
);
is_deeply(
   $qp->query_type( 'delete from foo where bar=1', $qr ),
   {  type => 'DELETE',
      rw   => 'write',
   },
   'query_type() delete'
);
is_deeply(
   $qp->query_type( 'update foo set bar="foo" where 1', $qr ),
   {  type => 'UPDATE',
      rw   => 'write',
   },
   'query_type() update'
);
is_deeply(
   $qp->query_type( 'truncate table bar', $qr ),
   {  type => 'TRUNCATE TABLE',
      rw   => 'write',
   },
   'query_type() truncate'
);
is_deeply(
   $qp->query_type( 'alter table foo add column (i int)', $qr ),
   {  type => 'ALTER TABLE',
      rw   => 'write',
   },
   'query_type() alter'
);
is_deeply(
   $qp->query_type( 'drop table foo', $qr ),
   {  type => 'DROP TABLE',
      rw   => 'write',
   },
   'query_type() drop'
);
is_deeply(
   $qp->query_type( 'show tables', $qr ),
   {  type => 'SHOW TABLES',
      rw   => undef,
   },
   'query_type() show tables'
);
is_deeply(
   $qp->query_type( 'show fields from foo', $qr ),
   {  type => 'SHOW FIELDS',
      rw   => undef,
   },
   'query_type() show fields'
);

# #############################################################################
# Issue 563: Lock tables is not distilled
# #############################################################################
is_deeply( [ $qp->get_tables('LOCK TABLES foo READ') ],
   [qw(foo)], 'LOCK TABLES foo READ' );
is_deeply( [ $qp->get_tables('LOCK TABLES foo WRITE') ],
   [qw(foo)], 'LOCK TABLES foo WRITE' );
is_deeply( [ $qp->get_tables('LOCK TABLES foo READ, bar WRITE') ],
   [qw(foo bar)], 'LOCK TABLES foo READ, bar WRITE' );
is_deeply( [ $qp->get_tables('LOCK TABLES foo AS als WRITE') ],
   [qw(foo)], 'LOCK TABLES foo AS als WRITE' );
is_deeply(
   [ $qp->get_tables('LOCK TABLES foo AS als1 READ, bar AS als2 WRITE') ],
   [qw(foo bar)], 'LOCK TABLES foo AS als READ, bar AS als2 WRITE' );
is_deeply( [ $qp->get_tables('LOCK TABLES foo als WRITE') ],
   [qw(foo)], 'LOCK TABLES foo als WRITE' );
is_deeply( [ $qp->get_tables('LOCK TABLES foo als1 READ, bar als2 WRITE') ],
   [qw(foo bar)], 'LOCK TABLES foo als READ, bar als2 WRITE' );

$sql = "CREATE TEMPORARY TABLE mk_upgrade AS SELECT col1, col2
        FROM foo, bar
        WHERE id = 1";
is_deeply( [ $qp->get_tables($sql) ],
   [qw(foo bar)], 'Get tables from special case multi-line query' );

is_deeply(
   [ $qp->get_tables('select * from (`mytable`)') ],
   [qw(`mytable`)],
   'Get tables when there are parens around table name (issue 781)',
);

is_deeply(
   [ $qp->get_tables('select * from (select * from mytable) t') ],
   [qw(mytable)], 'Does not consider subquery SELECT as a table (issue 781)',
);

is_deeply(
   [ $qp->get_tables('lock tables t1 as t5 read local, t2 low_priority write') ],
   [qw(t1 t2)], 'get_tables works for lowercased LOCK TABLES',
);

is_deeply(
   [ $qp->get_tables("LOAD DATA INFILE '/tmp/foo.txt' INTO TABLE db.tbl") ],
   [qw(db.tbl)],
   "LOAD DATA db.tbl"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
