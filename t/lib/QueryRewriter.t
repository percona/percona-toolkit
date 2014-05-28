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

use QueryRewriter;
use QueryParser;
use PerconaTest;

my $qp = new QueryParser();
my $qr = new QueryRewriter(QueryParser=>$qp);

# #############################################################################
# strip_comments()
# #############################################################################

is(
   $qr->strip_comments("select \n--bar\n foo"),
   "select \n\n foo",
   'Removes one-line comments',
);

is(
   $qr->strip_comments("select foo--bar\nfoo"),
   "select foo\nfoo",
   'Removes one-line comments without running them together',
);

is(
   $qr->strip_comments("select foo -- bar"),
   "select foo ",
   'Removes one-line comments at end of line',
);

is(
   $qr->strip_comments("select /*\nhello!*/ 1"),
   'select  1',
   'Stripped star comment',
);

is(
   $qr->strip_comments('select /*!40101 hello*/ 1'),
   'select /*!40101 hello*/ 1',
   'Left version star comment',
);

# #############################################################################
# fingerprint()
# #############################################################################

is(
   $qr->fingerprint(
      q{UPDATE groups_search SET  charter = '   -------3\'\' XXXXXXXXX.\n    \n    -----------------------------------------------------', show_in_list = 'Y' WHERE group_id='aaaaaaaa'}),
   'update groups_search set charter = ?, show_in_list = ? where group_id=?',
   'complex comments',
);

is(
   $qr->fingerprint("SELECT /*!40001 SQL_NO_CACHE */ * FROM `film`"),
   "mysqldump",
   'Fingerprints all mysqldump SELECTs together',
);

is(
   $qr->fingerprint("CALL foo(1, 2, 3)"),
   "call foo",
   'Fingerprints stored procedure calls specially',
);


is(
   $qr->fingerprint('administrator command: Init DB'),
   'administrator command: Init DB',
   'Fingerprints admin commands as themselves',
);

is(
   $qr->fingerprint(
      q{REPLACE /*foo.bar:3/3*/ INTO checksum.checksum (db, tbl, }
      .q{chunk, boundaries, this_cnt, this_crc) SELECT 'foo', 'bar', }
      .q{2 AS chunk_num, '`id` >= 2166633', COUNT(*) AS cnt, }
      .q{LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `id`, `created_by`, }
      .q{`created_date`, `updated_by`, `updated_date`, `ppc_provider`, }
      .q{`account_name`, `provider_account_id`, `campaign_name`, }
      .q{`provider_campaign_id`, `adgroup_name`, `provider_adgroup_id`, }
      .q{`provider_keyword_id`, `provider_ad_id`, `foo`, `reason`, }
      .q{`foo_bar_bazz_id`, `foo_bar_baz`, CONCAT(ISNULL(`created_by`), }
      .q{ISNULL(`created_date`), ISNULL(`updated_by`), ISNULL(`updated_date`), }
      .q{ISNULL(`ppc_provider`), ISNULL(`account_name`), }
      .q{ISNULL(`provider_account_id`), ISNULL(`campaign_name`), }
      .q{ISNULL(`provider_campaign_id`), ISNULL(`adgroup_name`), }
      .q{ISNULL(`provider_adgroup_id`), ISNULL(`provider_keyword_id`), }
      .q{ISNULL(`provider_ad_id`), ISNULL(`foo`), ISNULL(`reason`), }
      .q{ISNULL(`foo_base_foo_id`), ISNULL(`fooe_foo_id`)))) AS UNSIGNED)), 10, }
      .q{16)) AS crc FROM `foo`.`bar` USE INDEX (`PRIMARY`) WHERE }
      .q{(`id` >= 2166633); }),
   'percona-toolkit',
   'Fingerprints mk-table-checksum queries together',
);

is(
   $qr->fingerprint("use `foo`"),
   "use ?",
   'Removes identifier from USE',
);

is(
   $qr->fingerprint("select \n--bar\n foo"),
   "select foo",
   'Removes one-line comments in fingerprints',
);


is(
   $qr->fingerprint("select foo--bar\nfoo"),
   "select foo foo",
   'Removes one-line comments in fingerprint without mushing things together',
);

is(
   $qr->fingerprint("select foo -- bar\n"),
   "select foo ",
   'Removes one-line EOL comments in fingerprints',
);

# This one is too expensive!
#is(
#   $qr->fingerprint(
#      "select a,b ,c , d from tbl where a=5 or a = 5 or a=5 or a =5"),
#   "select a, b, c, d from tbl where a=? or a=? or a=? or a=?",
#   "Normalizes commas and equals",
#);

is(
   $qr->fingerprint("select null, 5.001, 5001. from foo"),
   "select ?, ?, ? from foo",
   "Handles bug from perlmonks thread 728718",
);

is(
   $qr->fingerprint("select 'hello', '\nhello\n', \"hello\", '\\'' from foo"),
   "select ?, ?, ?, ? from foo",
   "Handles quoted strings",
);


is(
   $qr->fingerprint("select 'hello'\n"),
   "select ?",
   "Handles trailing newline",
);

# This is a known deficiency, fixes seem to be expensive though.
is(
   $qr->fingerprint("select '\\\\' from foo"),
   "select '\\ from foo",
   "Does not handle all quoted strings",
);

is(
   $qr->fingerprint("select   foo"),
   "select foo",
   'Collapses whitespace',
);

is(
   $qr->fingerprint('SELECT * from foo where a = 5'),
   'select * from foo where a = ?',
   'Lowercases, replaces integer',
);

is(
   $qr->fingerprint('select 0e0, +6e-30, -6.00 from foo where a = 5.5 or b=0.5 or c=.5'),
   'select ?, ?, ? from foo where a = ? or b=? or c=?',
   'Floats',
);

is(
   $qr->fingerprint("select 0x0, x'123', 0b1010, b'10101' from foo"),
   'select ?, ?, ?, ? from foo',
   'Hex/bit',
);

is(
   $qr->fingerprint(" select  * from\nfoo where a = 5"),
   'select * from foo where a = ?',
   'Collapses whitespace',
);

is(
   $qr->fingerprint("select * from foo where a in (5) and b in (5, 8,9 ,9 , 10)"),
   'select * from foo where a in(?+) and b in(?+)',
   'IN lists',
);

is(
   $qr->fingerprint("select foo_1 from foo_2_3"),
   'select foo_? from foo_?_?',
   'Numeric table names',
);

# 123f00 => ?oo because f "looks like it could be a number".
is(
   $qr->fingerprint("select 123foo from 123foo", { prefixes => 1 }),
   'select ?oo from ?oo',
   'Numeric table name prefixes',
);

is(
   $qr->fingerprint("select 123_foo from 123_foo", { prefixes => 1 }),
   'select ?_foo from ?_foo',
   'Numeric table name prefixes with underscores',
);

is(
   $qr->fingerprint("insert into abtemp.coxed select foo.bar from foo"),
   'insert into abtemp.coxed select foo.bar from foo',
   'A string that needs no changes',
);

is(
   $qr->fingerprint('insert into foo(a, b, c) values(2, 4, 5)'),
   'insert into foo(a, b, c) values(?+)',
   'VALUES lists',
);


is(
   $qr->fingerprint('insert into foo(a, b, c) values(2, 4, 5) , (2,4,5)'),
   'insert into foo(a, b, c) values(?+)',
   'VALUES lists with multiple ()',
);

is(
   $qr->fingerprint('insert into foo(a, b, c) value(2, 4, 5)'),
   'insert into foo(a, b, c) value(?+)',
   'VALUES lists with VALUE()',
);

is(
   $qr->fingerprint('select * from foo limit 5'),
   'select * from foo limit ?',
   'limit alone',
);

is(
   $qr->fingerprint('select * from foo limit 5, 10'),
   'select * from foo limit ?',
   'limit with comma-offset',
);

is(
   $qr->fingerprint('select * from foo limit 5 offset 10'),
   'select * from foo limit ?',
   'limit with offset',
);

is(
   $qr->fingerprint('select 1 union select 2 union select 4'),
   'select ? /*repeat union*/',
   'union fingerprints together',
);

is(
   $qr->fingerprint('select 1 union all select 2 union all select 4'),
   'select ? /*repeat union all*/',
   'union all fingerprints together',
);

is(
   $qr->fingerprint(
      q{select * from (select 1 union all select 2 union all select 4) as x }
      . q{join (select 2 union select 2 union select 3) as y}),
   q{select * from (select ? /*repeat union all*/) as x }
      . q{join (select ? /*repeat union*/) as y},
   'union all fingerprints together',
);

# Issue 322: mk-query-digest segfault before report
is(
   $qr->fingerprint( load_file('t/lib/samples/huge_replace_into_values.txt') ),
   q{replace into `film_actor` values(?+)},
   'huge replace into values() (issue 322)',
);
is(
   $qr->fingerprint( load_file('t/lib/samples/huge_insert_ignore_into_values.txt') ),
   q{insert ignore into `film_actor` values(?+)},
   'huge insert ignore into values() (issue 322)',
);
is(
   $qr->fingerprint( load_file('t/lib/samples/huge_explicit_cols_values.txt') ),
   q{insert into foo (a,b,c,d,e,f,g,h) values(?+)},
   'huge insert with explicit columns before values() (issue 322)',
);

# Those ^ aren't huge enough.  This one is 1.2M large. 
my $zcat = `uname` =~ m/Darwin/ ? 'gzcat' : 'zcat';
my $huge_insert = `$zcat $trunk/t/lib/samples/slowlogs/slow039.txt.gz | tail -n 1`;
is(
   $qr->fingerprint($huge_insert),
   q{insert into the_universe values(?+)},
   'truly huge insert 1/2 (issue 687)'
);
$huge_insert = `$zcat $trunk/t/lib/samples/slowlogs/slow040.txt.gz | tail -n 2`;
is(
   $qr->fingerprint($huge_insert),
   q{insert into the_universe values(?+)},
   'truly huge insert 2/2 (issue 687)'
);

# Issue 1030: Fingerprint can remove ORDER BY ASC
is(
   $qr->fingerprint(
      "select c from t where i=1 order by c asc",
   ),
   "select c from t where i=? order by c",
   "Remove ASC from ORDER BY"
);
is(
   $qr->fingerprint(
      "select * from t where i=1 order by a, b ASC, d DESC, e asc",
   ),
   "select * from t where i=? order by a, b, d desc, e",
   "Remove only ASC from ORDER BY"
);
is(
   $qr->fingerprint(
      "select * from t where i=1      order            by 
      a,  b          ASC, d    DESC,    
                             
                             e asc",
   ),
   "select * from t where i=? order by a, b, d desc, e",
   "Remove ASC from spacey ORDER BY"
);

is(
   $qr->fingerprint("LOAD DATA INFILE '/tmp/foo.txt' INTO db.tbl"),
   "load data infile ? into db.tbl",
   "Fingerprint LOAD DATA INFILE"
);

# fingerprint MD5 checksums, 32 char hex strings.  This is a
# special feature used by pt-fingerprint.
$qr = new QueryRewriter(
   QueryParser     => $qp,
   match_md5_checksums => 1,
);

is(
   $qr->fingerprint(
      "SELECT * FROM db.fbc5e685a5d3d45aa1d0347fdb7c4d35_temp where id=1"
   ),
   "select * from db.?_temp where id=?",
   "Fingerprint db.MD5_tbl"
);

is(
   $qr->fingerprint(
      "SELECT * FROM db.temp_fbc5e685a5d3d45aa1d0347fdb7c4d35 where id=1"
   ),
   "select * from db.temp_? where id=?",
   "Fingerprint db.tbl_MD5"
);

$qr = new QueryRewriter(
   QueryParser     => $qp,
   match_md5_checksums => 1,
   match_embedded_numbers => 1,
);

is(
   $qr->fingerprint(
      "SELECT * FROM db.fbc5e685a5d3d45aa1d0347fdb7c4d35_temp where id=1"
   ),
   "select * from db.?_temp where id=?",
   "Fingerprint db.MD5_tbl (with match_embedded_numbers)"
);

is(
   $qr->fingerprint(
      "SELECT * FROM db.temp_fbc5e685a5d3d45aa1d0347fdb7c4d35 where id=1"
   ),
   "select * from db.temp_? where id=?",
   "Fingerprint db.tbl_MD5 (with match_embedded_numbers)"
);

$qr = new QueryRewriter(
   QueryParser => $qp,
   match_embedded_numbers => 1,
);

is(
   $qr->fingerprint(
      "SELECT * FROM prices.rt_5min where id=1"
   ),
   "select * from prices.rt_5min where id=?",
   "Fingerprint db.tbl<number>name (preserve number)"
);


is(
   $qr->fingerprint(
      "/* -- S++ SU ABORTABLE -- spd_user: rspadim */SELECT SQL_SMALL_RESULT SQL_CACHE DISTINCT centro_atividade FROM est_dia WHERE unidade_id=1001 AND item_id=67 AND item_id_red=573"
   ),
   "select sql_small_result sql_cache distinct centro_atividade from est_dia where unidade_id=? and item_id=? and item_id_red=?",
   "Fingerprint /* -- comment */ SELECT (bug 1174956)"
);


# issue 965553

is(
   $qr->fingerprint('SELECT * FROM tbl WHERE id=1 AND flag=true AND trueflag=FALSE'),
   'select * from tbl where id=? and flag=? and trueflag=?',
   'boolean values abstracted correctly',
);


# #############################################################################
# convert_to_select()
# #############################################################################

is($qr->convert_to_select(), undef, 'No query');

is(
   $qr->convert_to_select(
      'select * from tbl where id = 1'
   ),
   'select * from tbl where id = 1',
   'Does not convert select to select',
);

is(
   $qr->convert_to_select(q{INSERT INTO foo.bar (col1, col2, col3)
       VALUES ('unbalanced(', 'val2', 3)}),
   q{select * from  foo.bar  where col1='unbalanced(' and  }
   . q{col2= 'val2' and  col3= 3},
   'unbalanced paren inside a string in VALUES',
);

# convert REPLACE #############################################################

is(
   $qr->convert_to_select(
      'replace into foo select * from bar',
   ),
   'select * from bar',
   'convert REPLACE SELECT',
);

is(
   $qr->convert_to_select(
      'replace into foo select`faz` from bar',
   ),
   'select`faz` from bar',
   'convert REPLACE SELECT`col`',
);

is(
   $qr->convert_to_select(
      'replace into foo(a, b, c) values(1, 3, 5) on duplicate key update foo=bar',
   ),
   'select * from  foo where a=1 and  b= 3 and  c= 5',
   'convert REPLACE (cols) VALUES ON DUPE KEY',
);

is(
   $qr->convert_to_select(
      'replace into foo(a, b, c) values(now(), "3", 5)',
   ),
   'select * from  foo where a=now() and  b= "3" and  c= 5',
   'convert REPLACE (cols) VALUES (now())',
);

is(
   $qr->convert_to_select(
      'replace into foo(a, b, c) values(current_date - interval 1 day, "3", 5)',
   ),
   'select * from  foo where a=current_date - interval 1 day and  b= "3" and  c= 5',
   'convert REPLACE (cols) VALUES (complex expression)',
);

is(
   $qr->convert_to_select(q{
REPLACE DELAYED INTO
`db1`.`tbl2`(`col1`,col2)
VALUES ('617653','2007-09-11')}),
   qq{select * from \n`db1`.`tbl2` where `col1`='617653' and col2='2007-09-11'},
   'convert REPLACE DELAYED (cols) VALUES',
);

is(
   $qr->convert_to_select(
      'replace into tbl set col1="a val", col2=123, col3=null',
   ),
   'select * from  tbl where col1="a val" and  col2=123 and  col3=null ',
   'convert REPLACE SET'
);

# convert INSERT ##############################################################

is(
   $qr->convert_to_select(
      'insert into foo(a, b, c) values(1, 3, 5)',
   ),
   'select * from  foo where a=1 and  b= 3 and  c= 5',
   'convert INSERT (cols) VALUES',
);

is(
   $qr->convert_to_select(
      'insert into foo(a, b, c) value(1, 3, 5)',
   ),
   'select * from  foo where a=1 and  b= 3 and  c= 5',
   'convert INSERT (cols) VALUE',
);

# Issue 599: mk-slave-prefetch doesn't parse INSERT IGNORE
is(
   $qr->convert_to_select(
      'insert ignore into foo(a, b, c) values(1, 3, 5)',
   ),
   'select * from  foo where a=1 and  b= 3 and  c= 5',
   'convert INSERT IGNORE (cols) VALUES',
);

is(
   $qr->convert_to_select(
      'INSERT IGNORE INTO Foo (clm1, clm2) VALUE (1,2)',
   ),
   'select * from  Foo  where clm1=1 and  clm2=2',
   'convert INSERT IGNORE (cols) VALUE',
);

is(
   $qr->convert_to_select(
      'insert into foo select * from bar join baz using (bat)',
   ),
   'select * from bar join baz using (bat)',
   'convert INSERT SELECT',
);

# Issue 600: mk-slave-prefetch doesn't parse INSERT INTO Table SET c1 = v1,
# c2 = v2 ...
is(
   $qr->convert_to_select(
      "INSERT INTO Table SET c1 = 'v1', c2 = 'v2', c3 = 'v3'",
   ),
   "select * from  Table where c1 = 'v1' and  c2 = 'v2' and  c3 = 'v3' ",
   'convert INSERT SET char cols',
);

is(
   $qr->convert_to_select(
      "INSERT INTO db.tbl SET c1=NULL,c2=42,c3='some value with spaces'",
   ),
   "select * from  db.tbl where c1=NULL and c2=42 and c3='some value with spaces' ",
   'convert INSERT SET NULL col, int col, char col with space',
);

is(
   $qr->convert_to_select(
      'insert into foo (col1) values (1) on duplicate key update',
   ),
   'select * from  foo  where col1=1',
   'convert INSERT (cols) VALUES ON DUPE KEY UPDATE'
);

is(
   $qr->convert_to_select(
      'insert into foo (col1) value (1) on duplicate key update',
   ),
   'select * from  foo  where col1=1',
   'convert INSERT (cols) VALUE ON DUPE KEY UPDATE'
);

is(
   $qr->convert_to_select(
      "insert into tbl set col='foo', col2='some val' on duplicate key update",
   ),
   "select * from  tbl where col='foo' and  col2='some val' ",
   'convert INSERT SET ON DUPE KEY UPDATE',
);

is(
   $qr->convert_to_select(
      'insert into foo select * from bar where baz=bat on duplicate key update',
   ),
   'select * from bar where baz=bat',
   'convert INSERT SELECT ON DUPE KEY UPDATE',
);

# convert UPDATE ##############################################################

is(
   $qr->convert_to_select(
      'update foo set bar=baz where bat=fiz',
   ),
   'select  bar=baz from foo where  bat=fiz',
   'update set',
);

is(
   $qr->convert_to_select(
      'update foo inner join bar using(baz) set big=little',
   ),
   'select  big=little from foo inner join bar using(baz) ',
   'delete inner join',
);

is(
   $qr->convert_to_select(
      'update foo set bar=baz limit 50',
   ),
   'select  bar=baz  from foo  limit 50 ',
   'update with limit',
);

is(
   $qr->convert_to_select(
q{UPDATE foo.bar
SET    whereproblem= '3364', apple = 'fish'
WHERE  gizmo='5091'}
   ),
   q{select     whereproblem= '3364', apple = 'fish' from foo.bar where   gizmo='5091'},
   'unknown issue',
);

# Insanity...
is(
   $qr->convert_to_select('
update db2.tbl1 as p
   inner join (
      select p2.col1, p2.col2
      from db2.tbl1 as p2
         inner join db2.tbl3 as ba
            on p2.col1 = ba.tbl3
      where col4 = 0
      order by priority desc, col1, col2
      limit 10
   ) as chosen on chosen.col1 = p.col1
      and chosen.col2 = p.col2
   set p.col4 = 149945'),
   'select  p.col4 = 149945 from db2.tbl1 as p
   inner join (
      select p2.col1, p2.col2
      from db2.tbl1 as p2
         inner join db2.tbl3 as ba
            on p2.col1 = ba.tbl3
      where col4 = 0
      order by priority desc, col1, col2
      limit 10
   ) as chosen on chosen.col1 = p.col1
      and chosen.col2 = p.col2 ',
   'SELECT in the FROM clause',
);

is(
   $qr->convert_to_select("UPDATE tbl SET col='wherex'WHERE crazy=1"),
   "select  col='wherex' from tbl where  crazy=1",
   "update with SET col='wherex'WHERE"
);

is($qr->convert_to_select(
   q{UPDATE GARDEN_CLUPL PL, GARDENJOB GC, APLTRACT_GARDENPLANT ABU SET }
   . q{GC.MATCHING_POT = 5, GC.LAST_GARDENPOT = 5, GC.LAST_NAME=}
   . q{'Rotary', GC.LAST_BUCKET='Pail', GC.LAST_UPDATE='2008-11-27 04:00:59'WHERE}
   . q{ PL.APLTRACT_GARDENPLANT_ID = GC.APLTRACT_GARDENPLANT_ID AND PL.}
   . q{APLTRACT_GARDENPLANT_ID = ABU.ID AND GC.MATCHING_POT = 0 AND GC.PERFORM_DIG=1}
   . q{ AND ABU.DIG = 6 AND ( ((SOIL-COST) > -80.0}
   . q{ AND BUGS < 60.0 AND (SOIL-COST) < 200.0) AND POTS < 10.0 )}),
   "select  GC.MATCHING_POT = 5, GC.LAST_GARDENPOT = 5, GC.LAST_NAME='Rotary', GC.LAST_BUCKET='Pail', GC.LAST_UPDATE='2008-11-27 04:00:59' from GARDEN_CLUPL PL, GARDENJOB GC, APLTRACT_GARDENPLANT ABU where  PL.APLTRACT_GARDENPLANT_ID = GC.APLTRACT_GARDENPLANT_ID AND PL.APLTRACT_GARDENPLANT_ID = ABU.ID AND GC.MATCHING_POT = 0 AND GC.PERFORM_DIG=1 AND ABU.DIG = 6 AND ( ((SOIL-COST) > -80.0 AND BUGS < 60.0 AND (SOIL-COST) < 200.0) AND POTS < 10.0 )",
   'update with no space between quoted string and where (issue 168)'
);

is(
   $qr->convert_to_select("UPDATE LOW_PRIORITY db.tbl SET field='new' WHERE id=1"),
   "select  field='new' from db.tbl where  id=1",
   "update with LOW_PRIORITY"
);

is(
   $qr->convert_to_select("UPDATE ignore db.tbl SET field='new' WHERE id=1"),
   "select  field='new' from db.tbl where  id=1",
   "update with IGNORE"
);

# convert DELETE ##############################################################

is(
   $qr->convert_to_select(
      'delete from foo where bar = baz',
   ),
   'select * from  foo where bar = baz',
   'delete',
);

is(
   $qr->convert_to_select(q{delete foo.bar b from foo.bar b left join baz.bat c on a=b where nine>eight}),
   'select 1 from  foo.bar b left join baz.bat c on a=b where nine>eight',
   'Do not select * from a join',
);

is(
   $qr->convert_to_select("DELETE LOW_PRIORITY FROM tbl WHERE id=1"),
   "select * from  tbl WHERE id=1",
   "delete with LOW_PRIORITY"
);

is(
   $qr->convert_to_select("delete ignore from tbl WHERE id=1"),
   "select * from  tbl WHERE id=1",
   "delete with IGNORE"
);

is(
   $qr->convert_to_select("delete from file where id='ima-long-uuid-string'"),
   "select * from  file where id='ima-long-uuid-string'",
   "Peter's DELTE"
);

# do not convert subqueries ###################################################

is(
   $qr->convert_to_select("UPDATE mybbl_MBMessage SET groupId = (select groupId from Group_ where name = 'Guest')"),
   undef,
   'Do not convert subquery'
);

# #############################################################################
# wrap_in_derived()
# #############################################################################

is($qr->wrap_in_derived(), undef, 'Cannot wrap undef');

is(
   $qr->wrap_in_derived(
      'select * from foo',
   ),
   'select 1 from (select * from foo) as x limit 1',
   'wrap in derived table',
);

is(
   $qr->wrap_in_derived('set timestamp=134'),
   'set timestamp=134',
   'Do not wrap non-SELECT queries',
);

# #############################################################################
# convert_select_list()
# #############################################################################

is(
   $qr->convert_select_list('select * from tbl'),
   'select 1 from tbl',
   'Star to one',
);

is(
   $qr->convert_select_list('select a, b, c from tbl'),
   'select isnull(coalesce( a, b, c )) from tbl',
   'column list to isnull/coalesce'
);

# #############################################################################
# shorten()
# #############################################################################

is(
   $qr->shorten("insert into t(a,b,c) values(a,b,c),(d,e,f),(g,h,i)"),
   "insert into t(a,b,c) values(a,b,c) /*... omitted ...*/",
   "shorten simple insert",
);

is(
   $qr->shorten("insert low_priority into t(a,b,c) values(a,b,c),(d,e,f),(g,h,i)"),
   "insert low_priority into t(a,b,c) values(a,b,c) /*... omitted ...*/",
   "shorten low_priority simple insert",
);

is(
   $qr->shorten("insert delayed into t(a,b,c) values(a,b,c),(d,e,f),(g,h,i)"),
   "insert delayed into t(a,b,c) values(a,b,c) /*... omitted ...*/",
   "shorten delayed simple insert",
);

is(
   $qr->shorten("insert high_priority into t(a,b,c) values(a,b,c),(d,e,f),(g,h,i)"),
   "insert high_priority into t(a,b,c) values(a,b,c) /*... omitted ...*/",
   "shorten high_priority simple insert",
);

is(
   $qr->shorten("insert ignore into t(a,b,c) values(a,b,c),(d,e,f),(g,h,i)"),
   "insert ignore into t(a,b,c) values(a,b,c) /*... omitted ...*/",
   "shorten ignore simple insert",
);

is(
   $qr->shorten("insert high_priority ignore into t(a,b,c) values(a,b,c),(d,e,f),(g,h,i)"),
   "insert high_priority ignore into t(a,b,c) values(a,b,c) /*... omitted ...*/",
   "shorten high_priority ignore simple insert",
);

is(
   $qr->shorten("replace low_priority into t(a,b,c) values(a,b,c),(d,e,f),(g,h,i)"),
   "replace low_priority into t(a,b,c) values(a,b,c) /*... omitted ...*/",
   "shorten replace low_priority",
);

is(
   $qr->shorten("replace delayed into t(a,b,c) values(a,b,c),(d,e,f),(g,h,i)"),
   "replace delayed into t(a,b,c) values(a,b,c) /*... omitted ...*/",
   "shorten replace delayed",
);

is(
   $qr->shorten("insert into t(a,b,c) values(a,b,c),(d,e,f),(g,h,i) on duplicate key update a = b"),
   "insert into t(a,b,c) values(a,b,c) /*... omitted ...*/on duplicate key update a = b",
   "shorten insert ... odku",
);

is(
   $qr->shorten(
      "select * from a where b in(" . join(',', 1..60) . ") and "
         . "a in(" . join(',', 1..5000) . ")", 1),
   "select * from a where b in(" . join(',', 1..20) . "/*... omitted 40 items ...*/)"
      . " and a in(" . join(',', 1..20) . "/*... omitted 4980 items ...*/)",
   "shorten two IN() lists of numbers",
);

is(
   $qr->shorten("select * from a", 1),
   "select * from a",
   "Does not shorten strings it does not match",
);

is(
   $qr->shorten("select * from a where b in(". join(',', 1..100) . ")", 1024),
   "select * from a where b in(". join(',', 1..100) . ")",
   "shorten IN() list numbers but not those that are already short enough",
);

is(
   $qr->shorten("select * from a where b in(" . join(',', 1..100) . "'a,b')", 1),
   "select * from a where b in(" . join(',', 1..20) . "/*... omitted 81 items ...*/)",
   "Test case to document that commas are expected to mess up omitted count",
);

is(
   $qr->shorten("select * from a where b in(1, 'a)b', " . join(',', 1..100) . ")", 1),
   "select * from a where b in(1, 'a)b', " . join(',', 1..100) . ")",
   "Test case to document that parens are expected to prevent shortening",
);

# #############################################################################
# distill()
# All tests below here are distill() tests.  There's a lot of them.
# #############################################################################

is(
   $qr->distill("SELECT /*!40001 SQL_NO_CACHE */ * FROM `film`"),
   "SELECT film",
   'Distills mysqldump SELECTs to selects',
);

is(
   $qr->distill("CALL foo(1, 2, 3)"),
   "CALL foo",
   'Distills stored procedure calls specially',
);

is(
   $qr->distill(
      q{REPLACE /*foo.bar:3/3*/ INTO checksum.checksum (db, tbl, }
      .q{chunk, boundaries, this_cnt, this_crc) SELECT 'foo', 'bar', }
      .q{2 AS chunk_num, '`id` >= 2166633', COUNT(*) AS cnt, }
      .q{LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `id`, `created_by`, }
      .q{`created_date`, `updated_by`, `updated_date`, `ppc_provider`, }
      .q{`account_name`, `provider_account_id`, `campaign_name`, }
      .q{`provider_campaign_id`, `adgroup_name`, `provider_adgroup_id`, }
      .q{`provider_keyword_id`, `provider_ad_id`, `foo`, `reason`, }
      .q{`foo_bar_bazz_id`, `foo_bar_baz`, CONCAT(ISNULL(`created_by`), }
      .q{ISNULL(`created_date`), ISNULL(`updated_by`), ISNULL(`updated_date`), }
      .q{ISNULL(`ppc_provider`), ISNULL(`account_name`), }
      .q{ISNULL(`provider_account_id`), ISNULL(`campaign_name`), }
      .q{ISNULL(`provider_campaign_id`), ISNULL(`adgroup_name`), }
      .q{ISNULL(`provider_adgroup_id`), ISNULL(`provider_keyword_id`), }
      .q{ISNULL(`provider_ad_id`), ISNULL(`foo`), ISNULL(`reason`), }
      .q{ISNULL(`foo_base_foo_id`), ISNULL(`fooe_foo_id`)))) AS UNSIGNED)), 10, }
      .q{16)) AS crc FROM `foo`.`bar` USE INDEX (`PRIMARY`) WHERE }
      .q{(`id` >= 2166633); }),
   'REPLACE SELECT checksum.checksum foo.bar',
   'Distills mk-table-checksum query',
);

is(
   $qr->distill("use `foo`"),
   "USE",
   'distills USE',
);

is(
   $qr->distill(q{delete foo.bar b from foo.bar b left join baz.bat c on a=b where nine>eight}),
   'DELETE foo.bar baz.bat',
   'distills and then collapses same tables',
);

is(
   $qr->distill("select \n--bar\n foo"),
   "SELECT",
   'distills queries from DUAL',
);

is(
   $qr->distill("select null, 5.001, 5001. from foo"),
   "SELECT foo",
   "distills simple select",
);

is(
   $qr->distill("select 'hello', '\nhello\n', \"hello\", '\\'' from foo"),
   "SELECT foo",
   "distills with quoted strings",
);

is(
   $qr->distill("select foo_1 from foo_2_3"),
   'SELECT foo_?_?',
   'distills numeric table names',
);

is(
   $qr->distill("insert into abtemp.coxed select foo.bar from foo"),
   'INSERT SELECT abtemp.coxed foo',
   'distills insert/select',
);

is(
   $qr->distill('insert into foo(a, b, c) values(2, 4, 5)'),
   'INSERT foo',
   'distills value lists',
);

is(
   $qr->distill('select 1 union select 2 union select 4'),
   'SELECT UNION',
   'distill unions together',
);

is(
   $qr->distill(
      'delete from foo where bar = baz',
   ),
   'DELETE foo',
   'distills delete',
);

is(
   $qr->distill('set timestamp=134'),
   'SET',
   'distills set',
);

is(
   $qr->distill(
      'replace into foo(a, b, c) values(1, 3, 5) on duplicate key update foo=bar',
   ),
   'REPLACE UPDATE foo',
   'distills ODKU',
);

is($qr->distill(
   q{UPDATE GARDEN_CLUPL PL, GARDENJOB GC, APLTRACT_GARDENPLANT ABU SET }
   . q{GC.MATCHING_POT = 5, GC.LAST_GARDENPOT = 5, GC.LAST_NAME=}
   . q{'Rotary', GC.LAST_BUCKET='Pail', GC.LAST_UPDATE='2008-11-27 04:00:59'WHERE}
   . q{ PL.APLTRACT_GARDENPLANT_ID = GC.APLTRACT_GARDENPLANT_ID AND PL.}
   . q{APLTRACT_GARDENPLANT_ID = ABU.ID AND GC.MATCHING_POT = 0 AND GC.PERFORM_DIG=1}
   . q{ AND ABU.DIG = 6 AND ( ((SOIL-COST) > -80.0}
   . q{ AND BUGS < 60.0 AND (SOIL-COST) < 200.0) AND POTS < 10.0 )}),
   'UPDATE GARDEN_CLUPL GARDENJOB APLTRACT_GARDENPLANT',
   'distills where there is alias and comma-join',
);

is(
   $qr->distill(q{SELECT STRAIGHT_JOIN distinct foo, bar FROM A, B, C}),
   'SELECT A B C',
   'distill with STRAIGHT_JOIN',
);

is (
   $qr->distill(q{
REPLACE DELAYED INTO
`db1`.`tbl2`(`col1`,col2)
VALUES ('617653','2007-09-11')}),
   'REPLACE db?.tbl?',
   'distills replace-delayed',
);

is(
   $qr->distill(
      'update foo inner join bar using(baz) set big=little',
   ),
   'UPDATE foo bar',
   'distills update-multi',
);

is(
   $qr->distill('
update db2.tbl1 as p
   inner join (
      select p2.col1, p2.col2
      from db2.tbl1 as p2
         inner join db2.tbl3 as ba
            on p2.col1 = ba.tbl3
      where col4 = 0
      order by priority desc, col1, col2
      limit 10
   ) as chosen on chosen.col1 = p.col1
      and chosen.col2 = p.col2
   set p.col4 = 149945'),
   'UPDATE SELECT db?.tbl?',
   'distills complex subquery',
);

is(
   $qr->distill(
      'replace into checksum.checksum select `last_update`, `foo` from foo.foo'),
   'REPLACE SELECT checksum.checksum foo.foo',
   'distill with reserved words');

is($qr->distill('SHOW STATUS'), 'SHOW STATUS', 'distill SHOW STATUS');

is($qr->distill('commit'), 'COMMIT', 'distill COMMIT');

is($qr->distill('FLUSH TABLES WITH READ LOCK'), 'FLUSH', 'distill FLUSH');

is($qr->distill('BEGIN'), 'BEGIN', 'distill BEGIN');

is($qr->distill('start'), 'START', 'distill START');

is($qr->distill('ROLLBACK'), 'ROLLBACK', 'distill ROLLBACK');

is(
   $qr->distill(
      'insert into foo select * from bar join baz using (bat)',
   ),
   'INSERT SELECT foo bar baz',
   'distills insert select',
);

is(
   $qr->distill('create database foo'),
   'CREATE DATABASE foo',
   'distills create database'
);
is(
   $qr->distill('create table foo'),
   'CREATE TABLE foo',
   'distills create table'
);
is(
   $qr->distill('alter database foo'),
   'ALTER DATABASE foo',
   'distills alter database'
);
is(
   $qr->distill('alter table foo'),
   'ALTER TABLE foo',
   'distills alter table'
);
is(
   $qr->distill('drop database foo'),
   'DROP DATABASE foo',
   'distills drop database'
);
is(
   $qr->distill('drop table foo'),
   'DROP TABLE foo',
   'distills drop table'
);
is(
   $qr->distill('rename database foo'),
   'RENAME DATABASE foo',
   'distills rename database'
);
is(
   $qr->distill('rename table foo'),
   'RENAME TABLE foo',
   'distills rename table'
);
is(
   $qr->distill('truncate table foo'),
   'TRUNCATE TABLE foo',
   'distills truncate table'
);

# Test generic distillation for memcached, http, etc.
my $trf = sub {
   my ( $query ) = @_;
   $query =~ s/(\S+ \S+?)(?:[?;].+)/$1/;
   return $query;
};

is(
   $qr->distill('get percona.com/', generic => 1, trf => $trf),
   'GET percona.com/',
   'generic distill HTTP get'
);

is(
   $qr->distill('get percona.com/page.html?some=thing', generic => 1, trf => $trf),
   'GET percona.com/page.html',
   'generic distill HTTP get with args'
);

is(
   $qr->distill('put percona.com/contacts.html', generic => 1, trf => $trf),
   'PUT percona.com/contacts.html',
   'generic distill HTTP put'
);

is(
   $qr->distill(
      'update foo set bar=baz where bat=fiz',
   ),
   'UPDATE foo',
   'distills update',
);

# Issue 563: Lock tables is not distilled
is(
   $qr->distill('LOCK TABLES foo WRITE'),
   'LOCK foo',
   'distills lock tables'
);
is(
   $qr->distill('LOCK TABLES foo READ, bar WRITE'),
   'LOCK foo bar',
   'distills lock tables (2 tables)'
);
is(
   $qr->distill('UNLOCK TABLES'),
   'UNLOCK',
   'distills unlock tables'
);

#  Issue 712: Queries not handled by "distill"
is(
   $qr->distill('XA START 0x123'),
   'XA_START',
   'distills xa start'
);
is(
   $qr->distill('XA PREPARE 0x123'),
   'XA_PREPARE',
   'distills xa prepare'
);
is(
   $qr->distill('XA COMMIT 0x123'),
   'XA_COMMIT',
   'distills xa commit'
);
is(
   $qr->distill('XA END 0x123'),
   'XA_END',
   'distills xa end'
);

is(
   $qr->distill("/* mysql-connector-java-5.1-nightly-20090730 ( Revision: \${svn.Revision} ) */SHOW VARIABLES WHERE Variable_name ='language' OR Variable_name =
   'net_write_timeout' OR Variable_name = 'interactive_timeout' OR
   Variable_name = 'wait_timeout' OR Variable_name = 'character_set_client' OR
   Variable_name = 'character_set_connection' OR Variable_name =
   'character_set' OR Variable_name = 'character_set_server' OR Variable_name
   = 'tx_isolation' OR Variable_name = 'transaction_isolation' OR
   Variable_name = 'character_set_results' OR Variable_name = 'timezone' OR
   Variable_name = 'time_zone' OR Variable_name = 'system_time_zone' OR
   Variable_name = 'lower_case_table_names' OR Variable_name =
   'max_allowed_packet' OR Variable_name = 'net_buffer_length' OR
   Variable_name = 'sql_mode' OR Variable_name = 'query_cache_type' OR
   Variable_name = 'query_cache_size' OR Variable_name = 'init_connect'"),
   'SHOW VARIABLES',
   'distills /* comment */SHOW VARIABLES'
);

# This is a list of all the types of syntax for SHOW on
# http://dev.mysql.com/doc/refman/5.0/en/show.html
my %status_tests = (
   'SHOW BINARY LOGS'                           => 'SHOW BINARY LOGS',
   'SHOW BINLOG EVENTS in "log_name"'           => 'SHOW BINLOG EVENTS',
   'SHOW CHARACTER SET LIKE "pattern"'          => 'SHOW CHARACTER SET',
   'SHOW COLLATION WHERE "something"'           => 'SHOW COLLATION',
   'SHOW COLUMNS FROM tbl'                      => 'SHOW COLUMNS',
   'SHOW FULL COLUMNS FROM tbl'                 => 'SHOW COLUMNS',
   'SHOW COLUMNS FROM tbl in db'                => 'SHOW COLUMNS',
   'SHOW COLUMNS FROM tbl IN db LIKE "pattern"' => 'SHOW COLUMNS',
   'SHOW CREATE DATABASE db_name'               => 'SHOW CREATE DATABASE',
   'SHOW CREATE SCHEMA db_name'                 => 'SHOW CREATE DATABASE',
   'SHOW CREATE FUNCTION func'                  => 'SHOW CREATE FUNCTION',
   'SHOW CREATE PROCEDURE proc'                 => 'SHOW CREATE PROCEDURE',
   'SHOW CREATE TABLE tbl_name'                 => 'SHOW CREATE TABLE',
   'SHOW CREATE VIEW vw_name'                   => 'SHOW CREATE VIEW',
   'SHOW DATABASES'                             => 'SHOW DATABASES',
   'SHOW SCHEMAS'                               => 'SHOW DATABASES',
   'SHOW DATABASES LIKE "pattern"'              => 'SHOW DATABASES',
   'SHOW DATABASES WHERE foo=bar'               => 'SHOW DATABASES',
   'SHOW ENGINE ndb status'                     => 'SHOW NDB STATUS',
   'SHOW ENGINE innodb status'                  => 'SHOW INNODB STATUS',
   'SHOW ENGINES'                               => 'SHOW ENGINES',
   'SHOW STORAGE ENGINES'                       => 'SHOW ENGINES',
   'SHOW ERRORS'                                => 'SHOW ERRORS',
   'SHOW ERRORS limit 5'                        => 'SHOW ERRORS',
   'SHOW COUNT(*) ERRORS'                       => 'SHOW ERRORS',
   'SHOW FUNCTION CODE func'                    => 'SHOW FUNCTION CODE',
   'SHOW FUNCTION STATUS'                       => 'SHOW FUNCTION STATUS',
   'SHOW FUNCTION STATUS LIKE "pattern"'        => 'SHOW FUNCTION STATUS',
   'SHOW FUNCTION STATUS WHERE foo=bar'         => 'SHOW FUNCTION STATUS',
   'SHOW GRANTS'                                => 'SHOW GRANTS',
   'SHOW GRANTS FOR user@localhost'             => 'SHOW GRANTS',
   'SHOW INDEX'                                 => 'SHOW INDEX',
   'SHOW INDEXES'                               => 'SHOW INDEX',
   'SHOW KEYS'                                  => 'SHOW INDEX',
   'SHOW INDEX FROM tbl'                        => 'SHOW INDEX',
   'SHOW INDEX FROM tbl IN db'                  => 'SHOW INDEX',
   'SHOW INDEX IN tbl FROM db'                  => 'SHOW INDEX',
   'SHOW INNODB STATUS'                         => 'SHOW INNODB STATUS',
   'SHOW LOGS'                                  => 'SHOW LOGS',
   'SHOW MASTER STATUS'                         => 'SHOW MASTER STATUS',
   'SHOW MUTEX STATUS'                          => 'SHOW MUTEX STATUS',
   'SHOW OPEN TABLES'                           => 'SHOW OPEN TABLES',
   'SHOW OPEN TABLES FROM db'                   => 'SHOW OPEN TABLES',
   'SHOW OPEN TABLES IN db'                     => 'SHOW OPEN TABLES',
   'SHOW OPEN TABLES IN db LIKE "pattern"'      => 'SHOW OPEN TABLES',
   'SHOW OPEN TABLES IN db WHERE foo=bar'       => 'SHOW OPEN TABLES',
   'SHOW OPEN TABLES WHERE foo=bar'             => 'SHOW OPEN TABLES',
   'SHOW PRIVILEGES'                            => 'SHOW PRIVILEGES',
   'SHOW PROCEDURE CODE proc'                   => 'SHOW PROCEDURE CODE',
   'SHOW PROCEDURE STATUS'                      => 'SHOW PROCEDURE STATUS',
   'SHOW PROCEDURE STATUS LIKE "pattern"'       => 'SHOW PROCEDURE STATUS',
   'SHOW PROCEDURE STATUS WHERE foo=bar'        => 'SHOW PROCEDURE STATUS',
   'SHOW PROCESSLIST'                           => 'SHOW PROCESSLIST',
   'SHOW FULL PROCESSLIST'                      => 'SHOW PROCESSLIST',
   'SHOW PROFILE'                               => 'SHOW PROFILE',
   'SHOW PROFILES'                              => 'SHOW PROFILES',
   'SHOW PROFILES CPU FOR QUERY 1'              => 'SHOW PROFILES CPU',
   'SHOW SLAVE HOSTS'                           => 'SHOW SLAVE HOSTS',
   'SHOW SLAVE STATUS'                          => 'SHOW SLAVE STATUS',
   'SHOW STATUS'                                => 'SHOW STATUS',
   'SHOW GLOBAL STATUS'                         => 'SHOW GLOBAL STATUS',
   'SHOW SESSION STATUS'                        => 'SHOW STATUS',
   'SHOW STATUS LIKE "pattern"'                 => 'SHOW STATUS',
   'SHOW STATUS WHERE foo=bar'                  => 'SHOW STATUS',
   'SHOW TABLE STATUS'                          => 'SHOW TABLE STATUS',
   'SHOW TABLE STATUS FROM db_name'             => 'SHOW TABLE STATUS',
   'SHOW TABLE STATUS IN db_name'               => 'SHOW TABLE STATUS',
   'SHOW TABLE STATUS LIKE "pattern"'           => 'SHOW TABLE STATUS',
   'SHOW TABLE STATUS WHERE foo=bar'            => 'SHOW TABLE STATUS',
   'SHOW TABLES'                                => 'SHOW TABLES',
   'SHOW FULL TABLES'                           => 'SHOW TABLES',
   'SHOW TABLES FROM db'                        => 'SHOW TABLES',
   'SHOW TABLES IN db'                          => 'SHOW TABLES',
   'SHOW TABLES LIKE "pattern"'                 => 'SHOW TABLES',
   'SHOW TABLES FROM db LIKE "pattern"'         => 'SHOW TABLES',
   'SHOW TABLES WHERE foo=bar'                  => 'SHOW TABLES',
   'SHOW TRIGGERS'                              => 'SHOW TRIGGERS',
   'SHOW TRIGGERS IN db'                        => 'SHOW TRIGGERS',
   'SHOW TRIGGERS FROM db'                      => 'SHOW TRIGGERS',
   'SHOW TRIGGERS LIKE "pattern"'               => 'SHOW TRIGGERS',
   'SHOW TRIGGERS WHERE foo=bar'                => 'SHOW TRIGGERS',
   'SHOW VARIABLES'                             => 'SHOW VARIABLES',
   'SHOW GLOBAL VARIABLES'                      => 'SHOW GLOBAL VARIABLES',
   'SHOW SESSION VARIABLES'                     => 'SHOW VARIABLES',
   'SHOW VARIABLES LIKE "pattern"'              => 'SHOW VARIABLES',
   'SHOW VARIABLES WHERE foo=bar'               => 'SHOW VARIABLES',
   'SHOW WARNINGS'                              => 'SHOW WARNINGS',
   'SHOW WARNINGS LIMIT 5'                      => 'SHOW WARNINGS',
   'SHOW COUNT(*) WARNINGS'                     => 'SHOW WARNINGS',
   'SHOW COUNT ( *) WARNINGS'                   => 'SHOW WARNINGS',
);

foreach my $key ( keys %status_tests ) {
   is($qr->distill($key), $status_tests{$key}, "distills $key");
}

is(
   $qr->distill('SHOW SLAVE STATUS'),
   'SHOW SLAVE STATUS',
   'distills SHOW SLAVE STATUS'
);
is(
   $qr->distill('SHOW INNODB STATUS'),
   'SHOW INNODB STATUS',
   'distills SHOW INNODB STATUS'
);
is(
   $qr->distill('SHOW CREATE TABLE'),
   'SHOW CREATE TABLE',
   'distills SHOW CREATE TABLE'
);

my @show = qw(COLUMNS GRANTS INDEX STATUS TABLES TRIGGERS WARNINGS);
foreach my $show ( @show ) {
   is(
      $qr->distill("SHOW $show"),
      "SHOW $show",
      "distills SHOW $show"
   );
}

#  Issue 735: mk-query-digest doesn't distill query correctly
is( 
	$qr->distill('SHOW /*!50002 GLOBAL */ STATUS'),
	'SHOW GLOBAL STATUS',
	"distills SHOW /*!50002 GLOBAL */ STATUS"
);

is( 
	$qr->distill('SHOW /*!50002 ENGINE */ INNODB STATUS'),
	'SHOW INNODB STATUS',
	"distills SHOW INNODB STATUS"
);

is( 
	$qr->distill('SHOW MASTER LOGS'),
	'SHOW MASTER LOGS',
	"distills SHOW MASTER LOGS"
);

is( 
	$qr->distill('SHOW GLOBAL STATUS'),
	'SHOW GLOBAL STATUS',
	"distills SHOW GLOBAL STATUS"
);

is( 
	$qr->distill('SHOW GLOBAL VARIABLES'),
	'SHOW GLOBAL VARIABLES',
	"distills SHOW GLOBAL VARIABLES"
);

is( 
	$qr->distill('administrator command: Statistics'),
	'ADMIN STATISTICS',
	"distills ADMIN STATISTICS"
);

# Issue 781: mk-query-digest doesn't distill or extract tables properly
is( 
	$qr->distill("SELECT `id` FROM (`field`) WHERE `id` = '10000016228434112371782015185031'"),
	'SELECT field',
	'distills SELECT clm from (`tbl`)'
);

is(  
	$qr->distill("INSERT INTO (`jedi_forces`) (name, side, email) values ('Anakin Skywalker', 'jedi', 'anakin_skywalker_at_jedi.sw')"),
	'INSERT jedi_forces',
	'distills INSERT INTO (`tbl`)' 
);

is(  
	$qr->distill("UPDATE (`jedi_forces`) set side = 'dark' and name = 'Lord Vader' where name = 'Anakin Skywalker'"),
	'UPDATE jedi_forces',
	'distills UPDATE (`tbl`)'
);

is(
	$qr->distill("select c from (tbl1 JOIN tbl2 on (id)) where x=y"),
	'SELECT tbl?',
	'distills SELECT (t1 JOIN t2)'
);

is(
	$qr->distill("insert into (t1) value('a')"),
	'INSERT t?',
	'distills INSERT (tbl)'
);

# Something that will (should) never distill.
is(
	$qr->distill("-- how /*did*/ `THIS` #happen?"),
	'',
	'distills nonsense'
);

is(
	$qr->distill("peek tbl poke db"),
	'',
	'distills non-SQL'
);

# Issue 1176: mk-query-digest incorrectly distills queries with certain keywords

# I want to see first how this is handled.  It's correct because the query
# really does read from tables a and c; table b is just an alias.
is(
   $qr->distill("select c from (select * from a) as b where exists (select * from c where id is null)"),
   "SELECT a c",
   "distills SELECT with subquery in FROM and WHERE"
);

is(
	$qr->distill("select c from t where col='delete'"),
	'SELECT t',
   'distills SELECT with keyword as value (issue 1176)'
);

is(
   $qr->distill('SELECT c, replace(foo, bar) FROM t WHERE col <> "insert"'),
   'SELECT t',
   'distills SELECT with REPLACE function (issue 1176)'
);

# LOAD DATA
# https://bugs.launchpad.net/percona-toolkit/+bug/821692
# INSERT and REPLACE without INTO
# https://bugs.launchpad.net/percona-toolkit/+bug/984053
is(
   $qr->distill("LOAD DATA LOW_PRIORITY LOCAL INFILE 'file' INTO TABLE tbl"),
   "LOAD DATA tbl",
   "distill LOAD DATA (bug 821692)"
);

is(
   $qr->distill("LOAD DATA LOW_PRIORITY LOCAL INFILE 'file' INTO TABLE `tbl`"),
   "LOAD DATA tbl",
   "distill LOAD DATA (bug 821692)"
);

is(
   $qr->distill("insert ignore_bar (id) values (4029731)"),
   "INSERT ignore_bar",
   "distill INSERT without INTO (bug 984053)"
);

is(
   $qr->distill("replace ignore_bar (id) values (4029731)"),
   "REPLACE ignore_bar",
   "distill REPLACE without INTO (bug 984053)"
);

# IF EXISTS
# https://bugs.launchpad.net/percona-toolkit/+bug/821690
is(
   $qr->distill("DROP TABLE IF EXISTS foo"),
   "DROP TABLE foo",
   "distill DROP TABLE IF EXISTS foo (bug 821690)"
);

is(
   $qr->distill("CREATE TABLE IF NOT EXISTS foo"),
   "CREATE TABLE foo",
   "distill CREATE TABLE IF NOT EXISTS foo",
);



# #############################################################################
# Done.
# #############################################################################
done_testing;
