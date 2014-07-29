#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 9;

use PerconaTest;
use BinaryLogParser;

my $p = new BinaryLogParser();

my $oktorun = 1;
my $sample  = "t/lib/samples/binlogs/";

test_log_parser(
   parser  => $p,
   file    => $sample."binlog001.txt",
   oktorun => sub { $oktorun = $_[0]; },
   result  => [
  {
    '@@session.character_set_client' => '8',
    '@@session.collation_connection' => '8',
    '@@session.collation_server' => '8',
    '@@session.foreign_key_checks' => '1',
    '@@session.sql_auto_is_null' => '1',
    '@@session.sql_mode' => '0',
    '@@session.time_zone' => '\'system\'',
    '@@session.unique_checks' => '1',
    Query_time => '20664',
    Thread_id => '104168',
    arg => 'BEGIN',
    bytes => 5,
    cmd => 'Query',
    end_log_pos => '498006652',
    error_code => '0',
    offset => '498006722',
    pos_in_log => 146,
    server_id => '21',
    timestamp => '1197046970',
    ts => '071207 12:02:50'
  },
  {
    Query_time => '20675',
    Thread_id => '104168',
    arg => 'update test3.tblo as o
         inner join test3.tbl2 as e on o.animal = e.animal and o.oid = e.oid
      set e.tblo = o.tblo,
          e.col3 = o.col3
      where e.tblo is null',
    bytes => 179,
    cmd => 'Query',
    db => 'test1',
    end_log_pos => '278',
    error_code => '0',
    offset => '498006789',
    pos_in_log => 605,
    server_id => '21',
    timestamp => '1197046927',
    ts => '071207 12:02:07'
  },
  {
    Query_time => '20704',
    Thread_id => '104168',
    arg => 'replace into test4.tbl9(tbl5, day, todo, comment)
 select distinct o.tbl5, date(o.col3), \'misc\', right(\'foo\', 50)
      from test3.tblo as o
         inner join test3.tbl2 as e on o.animal = e.animal and o.oid = e.oid
      where e.tblo is not null
         and o.col1 > 0
         and o.tbl2 is null
         and o.col3 >= date_sub(current_date, interval 30 day)',
    bytes => 363,
    cmd => 'Query',
    end_log_pos => '836',
    error_code => '0',
    offset => '498007067',
    pos_in_log => 953,
    server_id => '21',
    timestamp => '1197046928',
    ts => '071207 12:02:08'
  },
  {
    Query_time => '20664',
    Thread_id => '104168',
    arg => 'update test3.tblo as o inner join test3.tbl2 as e
 on o.animal = e.animal and o.oid = e.oid
      set o.tbl2 = e.tbl2,
          e.col9 = now()
      where o.tbl2 is null',
    bytes => 170,
    cmd => 'Query',
    end_log_pos => '1161',
    error_code => '0',
    offset => '498007625',
    pos_in_log => 1469,
    server_id => '21',
    timestamp => '1197046970',
    ts => '071207 12:02:50'
  },
  {
    Xid => '4584956',
    arg => 'COMMIT',
    bytes => 6,
    cmd => 'Query',
    end_log_pos => '498007840',
    offset => '498007950',
    pos_in_log => 1793,
    server_id => '21',
    ts => '071207 12:02:50'
  },
  {
    Query_time => '20661',
    Thread_id => '103374',
    arg => 'insert into test1.tbl6
      (day, tbl5, misccol9type, misccol9, metric11, metric12, secs)
      values
      (convert_tz(current_timestamp,\'EST5EDT\',\'PST8PDT\'), \'239\', \'foo\', \'bar\', 1, \'1\', \'16.3574378490448\')
      on duplicate key update metric11 = metric11 + 1,
         metric12 = metric12 + values(metric12), secs = secs + values(secs)',
    bytes => 341,
    cmd => 'Query',
    end_log_pos => '417',
    error_code => '0',
    offset => '498007977',
    pos_in_log => 1889,
    server_id => '21',
    timestamp => '1197046973',
    ts => '071207 12:02:53'
  },
  {
    Xid => '4584964',
    arg => 'COMMIT',
    bytes => 6,
    cmd => 'Query',
    end_log_pos => '498008284',
    offset => '498008394',
    pos_in_log => 2383,
    server_id => '21',
    ts => '071207 12:02:53'
  },
  {
    Query_time => '20661',
    Thread_id => '103374',
    arg => 'update test2.tbl8
      set last2metric1 = last1metric1, last2time = last1time,
         last1metric1 = last0metric1, last1time = last0time,
         last0metric1 = ondeckmetric1, last0time = now()
      where tbl8 in (10800712)',
    bytes => 228,
    cmd => 'Query',
    end_log_pos => '314',
    error_code => '0',
    offset => '498008421',
    pos_in_log => 2479,
    server_id => '21',
    timestamp => '1197046973',
    ts => '071207 12:02:53'
  },
  {
    Xid => '4584965',
    arg => 'COMMIT',
    bytes => 6,
    cmd => 'Query',
    end_log_pos => '498008625',
    offset => '498008735',
    pos_in_log => 2860,
    server_id => '21',
    ts => '071207 12:02:53'
  },
  {
    arg => 'ROLLBACK /* added by mysqlbinlog */
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/',
    bytes => 87,
    cmd => 'Query',
    pos_in_log => 3066,
    ts => undef
  }
]
);

is(
   $oktorun,
   0,
   'Sets oktorun'
);

test_log_parser(
   parser => $p,
   file   => $sample."binlog002.txt",
   result => [
  {
    arg => 'ROLLBACK',
    bytes => 8,
    cmd => 'Query',
    end_log_pos => '98',
    offset => '4',
    pos_in_log => 146,
    server_id => '12345',
    ts => '090722  7:21:41'
  },
  {
    '@@session.character_set_client' => '8',
    '@@session.collation_connection' => '8',
    '@@session.collation_server' => '8',
    '@@session.foreign_key_checks' => '1',
    '@@session.sql_auto_is_null' => '1',
    '@@session.sql_mode' => '0',
    '@@session.unique_checks' => '1',
    Query_time => '0',
    Thread_id => '3',
    arg => 'create database d',
    bytes => 17,
    cmd => 'Query',
    end_log_pos => '175',
    error_code => '0',
    offset => '98',
    pos_in_log => 381,
    server_id => '12345',
    timestamp => '1248268919',
    ts => '090722  7:21:59'
  },
  {
    Query_time => '0',
    Thread_id => '3',
    arg => 'create table foo (i int)',
    bytes => 24,
    cmd => 'Query',
    db => 'd',
    end_log_pos => '259',
    error_code => '0',
    offset => '175',
    pos_in_log => 795,
    server_id => '12345',
    timestamp => '1248268936',
    ts => '090722  7:22:16'
  },
  {
    Query_time => '0',
    Thread_id => '3',
    arg => 'insert foo values (1),(2)',
    bytes => 25,
    cmd => 'Query',
    end_log_pos => '344',
    error_code => '0',
    offset => '259',
    pos_in_log => 973,
    server_id => '12345',
    timestamp => '1248268944',
    ts => '090722  7:22:24'
  },
  {
    arg => 'ROLLBACK /* added by mysqlbinlog */
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/',
    bytes => 87,
    cmd => 'Query',
    pos_in_log => 1152,
    ts => undef
  }
   ]
);

# #############################################################################
# Issue 1335960  - Cannot parse MySQL 5.6 Binary Logs 
#                  because CRC32 checksum was introduced
# #############################################################################

test_log_parser(
   parser  => $p,
   file    => $sample."binlog-CRC32.txt",
   oktorun => sub { $oktorun = $_[0]; },
   result  => [
   {
     arg => q[BINLOG '
hUu0Uw85MAAAdAAAAHgAAAABAAQANS42LjE3LWxvZwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAEzgNAAgAEgAEBAQEEgAAXAAEGggAAAAICAgCAAAACgoKGRkAAWfc
INs=
'],
     bytes => 169,
     cmd => 'Query',
     end_log_pos => '120',
     offset => '4',
     pos_in_log => 192,
     server_id => '12345',
     ts => '140702 15:12:21'
   },
   {
     '@@session.auto_increment_increment' => '1',
     '@@session.auto_increment_offset' => '1',
     '@@session.autocommit' => '1',
     '@@session.character_set_client' => '33',
     '@@session.collation_connection' => '33',
     '@@session.collation_database' => 'default',
     '@@session.collation_server' => '8',
     '@@session.foreign_key_checks' => '1',
     '@@session.lc_time_names' => '0',
     '@@session.pseudo_thread_id' => '14',
     '@@session.sql_auto_is_null' => '0',
     '@@session.sql_mode' => '1073741824',
     '@@session.time_zone' => '\'system\'',
     '@@session.unique_checks' => '1',
     Query_time => '0',
     Thread_id => '14',
     arg => 'BEGIN',
     bytes => 5,
     cmd => 'Query',
     end_log_pos => '204',
     error_code => '0',
     offset => '120',
     pos_in_log => 574,
     server_id => '12345',
     timestamp => '1404326011',
     ts => '140702 15:33:31'
   },
   {
     arg => '140702 15:33:31 server id 12345  end_log_pos 437 CRC32 0x7f23afd0 	Query	thread_id=14	exec_time=0	error_code=0
use `sakila`
SET TIMESTAMP=1404326011/*!*/
insert into film values (NULL,"Contact","Extraterrestrials contact earth", 2005, 1,1,24,5.55,120,25,\'PG\',\'Trailers\',now())
/*!*/'
,
     bytes => 282,
     cmd => 'Query',
     pos_in_log => 1390,
     ts => undef
   },
   {
     Xid => '285',
     arg => 'T',
     bytes => 1,
     cmd => 'Query',
     end_log_pos => '468',
     offset => '437',
     pos_in_log => 1682,
     server_id => '12345',
     ts => '140702 15:33:31'
   },
   {
     arg => 'ROLLBACK /* added by mysqlbinlog */
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=0*/',
     bytes => 132,
     cmd => 'Query',
     pos_in_log => 1794,
     ts => undef
   }

]
);




# #############################################################################
# Issue 606: Unknown event type Rotate at ./mk-slave-prefetch
# #############################################################################
test_log_parser(
   parser => $p,
   file   => $sample."binlog006.txt",
   result => [],
);

# #############################################################################
# Done.
# #############################################################################
exit;
