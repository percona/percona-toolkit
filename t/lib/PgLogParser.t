#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 41;

use PgLogParser;
use SysLogParser;
use MaatkitTest;

my $p = new PgLogParser;

# Run some tests of duration_to_secs().
my @duration_tests = (
   ['10.870 ms'     => '0.01087'],
   ['0.084312 sec'  => '0.084312'],
);
foreach my $test ( @duration_tests ) {
   is (
      $p->duration_to_secs($test->[0]),
      $test->[1],
      "Duration for $test->[0] == $test->[1]");
}

# duration_to_secs() should not accept garbage at the end of its argument.
throws_ok (
   sub {
      $p->duration_to_secs('duration: 1.565 ms  statement: SELECT 1');
   },
   qr/Unknown suffix/,
   'duration_to_secs does not like crap at the end',
);

# Tests of 'pending'.
is($p->pending, undef, 'Nothing in pending');
is_deeply([$p->pending('foo', 1)], ['foo', 1, undef], 'Store foo in pending');
is_deeply([$p->pending], ['foo', 1, 1], 'Get foo from pending');
is($p->pending, undef, 'Nothing in pending');

# Tests of 'get_meta'
my @meta = (
   ['c=4b7074b4.985,u=fred,D=jim', {
      Session_id => '4b7074b4.985',
      user       => 'fred',
      db         => 'jim',
   }],
   ['c=4b7074b4.985, user=fred, db=jim', {
      Session_id => '4b7074b4.985',
      user       => 'fred',
      db         => 'jim',
   }],
   ['c=4b7074b4.985 user=fred db=jim', {
      Session_id => '4b7074b4.985',
      user       => 'fred',
      db         => 'jim',
   }],
);
foreach my $meta ( @meta ) {
   is_deeply({$p->get_meta($meta->[0])}, $meta->[1], "Meta for $meta->[0]");
}

# A simple log of a session.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-log-001.txt',
   result => [
      {  ts            => '2010-02-08 15:31:48.685',
         host          => '[local]',
         db            => '[unknown]',
         user          => '[unknown]',
         arg           => 'connection received',
         Session_id    => '4b7074b4.985',
         pos_in_log    => 0,
         bytes         => 19,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-08 15:31:48.687',
         user          => 'fred',
         db            => 'fred',
         arg           => 'connection authorized',
         Session_id    => '4b7074b4.985',
         pos_in_log    => 107,
         bytes         => 21,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-08 15:31:50.872',
         db            => 'fred',
         user          => 'fred',
         arg           => 'select 1;',
         Query_time    => '0.01087',
         Session_id    => '4b7074b4.985',
         pos_in_log    => 217,
         bytes         => length('select 1;'),
         cmd           => 'Query',
      },
      {  ts            => '2010-02-08 15:31:58.515',
         db            => 'fred',
         user          => 'fred',
         arg           => "select\n1;",
         Query_time    => '0.013918',
         Session_id    => '4b7074b4.985',
         pos_in_log    => 384,
         bytes         => length("select\n1;"),
         cmd           => 'Query',
      },
      {  ts            => '2010-02-08 15:32:06.988',
         db            => 'fred',
         user          => 'fred',
         host          => '[local]',
         arg           => 'disconnection',
         Session_id    => '4b7074b4.985',
         pos_in_log    => 552,
         bytes         => length('disconnection'),
         cmd           => 'Admin',
      },
   ],
);

# A log that has no fancy line-prefix with user/db/session info.  It also begins
# with an entry whose header is missing.  And it ends with a line that has no
# 'duration' line afterwards.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-log-002.txt',
   result => [
      {  ts            => '2004-05-07 11:58:22',
         arg           => "SELECT groups.group_name,groups.unix_group_name,\n"
                           . "\tgroups.type_id,users.user_name,users.realname,\n"
                           . "\tnews_bytes.forum_id,news_bytes.summary,news_bytes.post_date,news_bytes.details \n"
                           . "\tFROM users,news_bytes,groups \n"
                           . "\tWHERE news_bytes.group_id='98' AND news_bytes.is_approved <> '4' \n"
                           . "\tAND users.user_id=news_bytes.submitted_by \n"
                           . "\tAND news_bytes.group_id=groups.group_id \n"
                           . "\tORDER BY post_date DESC LIMIT 10 OFFSET 0",
         pos_in_log    => 147,
         bytes         => 404,
         cmd           => 'Query',
         Query_time    => '0.00268',
      },
      {  ts            => '2004-05-07 11:58:36',
         arg           => 'begin; select getdatabaseencoding(); commit',
         cmd           => 'Query',
         pos_in_log    => 641,
         bytes         => 43,
      },
   ],
);

# A log that has no line-prefix at all.  It also has durations and statements on
# the same line.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-log-003.txt',
   result => [
      {  arg           => "SELECT * FROM users WHERE user_id='692'",
         pos_in_log    => 0,
         bytes         => 39,
         cmd           => 'Query',
         Query_time    => '0.001565',
      },
      {  arg           => "SELECT groups.group_name,groups.unix_group_name,\n"
                          . "\t\tgroups.type_id,users.user_name,users.realname,\n"
                          . "\t\tnews_bytes.forum_id,news_bytes.summary,news_bytes.post_date,news_bytes.details \n"
                          . "\t\tFROM users,news_bytes,groups \n"
                          . "\t\tWHERE news_bytes.is_approved=1 \n"
                          . "\t\tAND users.user_id=news_bytes.submitted_by \n"
                          . "\t\tAND news_bytes.group_id=groups.group_id \n"
                          . "\t\tORDER BY post_date DESC LIMIT 5 OFFSET 0",
         cmd           => 'Query',
         pos_in_log    => 77,
         bytes         => 376,
         Query_time    => '0.00164',
      },
      {  arg           => "SELECT total FROM forum_group_list_vw WHERE group_forum_id='4606'",
         pos_in_log    => 498,
         bytes         => 65,
         cmd           => 'Query',
         Query_time    => '0.000529',
      },
   ],
);

# A simple log of a session.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-log-004.txt',
   result => [
      {  ts            => '2010-02-10 08:39:56.835',
         host          => '[local]',
         db            => '[unknown]',
         user          => '[unknown]',
         arg           => 'connection received',
         Session_id    => '4b72b72c.b44',
         pos_in_log    => 0,
         bytes         => 19,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-10 08:39:56.838',
         user          => 'fred',
         db            => 'fred',
         arg           => 'connection authorized',
         Session_id    => '4b72b72c.b44',
         pos_in_log    => 107,
         bytes         => 21,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-10 08:40:34.681',
         db            => 'fred',
         user          => 'fred',
         arg           => 'select 1;',
         Query_time    => '0.001308',
         Session_id    => '4b72b72c.b44',
         pos_in_log    => 217,
         bytes         => length('select 1;'),
         cmd           => 'Query',
      },
      {  ts            => '2010-02-10 08:44:31.368',
         db            => 'fred',
         user          => 'fred',
         host          => '[local]',
         arg           => 'disconnection',
         Session_id    => '4b72b72c.b44',
         pos_in_log    => 321,
         bytes         => length('disconnection'),
         cmd           => 'Admin',
      },
   ],
);

# A log that shows that continuation lines don't have to start with a TAB, and
# not all queries must be followed by a duration.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-log-005.txt',
   result => [
      {  ts            => '2004-05-07 12:00:01',
         arg           => 'begin; select getdatabaseencoding(); commit',
         pos_in_log    => 0,
         bytes         => 43,
         cmd           => 'Query',
         Query_time    => '0.000801',
      },
      {  ts            => '2004-05-07 12:00:01',
         arg           => "update users set unix_status = 'A' where user_id in (select\n"
                         . "distinct u.user_id from users u, user_group ug WHERE\n"
                         . "u.user_id=ug.user_id and ug.cvs_flags='1' and u.status='A')",
         pos_in_log    => 126,
         bytes         => 172,
         cmd           => 'Query',
      },
      {  ts            => '2004-05-07 12:00:01',
         arg           => 'SELECT 1 FROM ONLY "public"."supported_languages" x '
                           . 'WHERE "language_id" = $1 FOR UPDATE OF x',
         pos_in_log    => 332,
         bytes         => 92,
         cmd           => 'Query',
      },
   ],
);

# A log with an error.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-log-006.txt',
   result => [
      {  ts            => '2004-05-07 12:01:06',
         arg           => 'SELECT plugin_id, plugin_name FROM plugins',
         pos_in_log    => 0,
         bytes         => 42,
         cmd           => 'Query',
         Query_time    => '0.002161',
      },
      {  ts            => '2004-05-07 12:01:06',
         arg           => "SELECT \n\t\t\t\tgroups.type,\n"
                           . "\t\t\t\tnews_bytes.details \n"
                           . "\t\t\tFROM \n"
                           . "\t\t\t\tnews_bytes,\n"
                           . "\t\t\t\tgroups \n"
                           . "\t\t\tWHERE \n"
                           . "\t\t\t\tnews_bytes.group_id=groups.group_id \n"
                           . "\t\t\tORDER BY \n"
                           . "\t\t\t\tdate \n"
                           . "\t\t\tDESC LIMIT 30 OFFSET 0",
         pos_in_log    => 125,
         bytes         => 185,
         cmd           => 'Query',
         Error_msg     => 'No such attribute groups.type',
      },
      {  ts            => '2004-05-07 12:01:06',
         arg           => 'SELECT plugin_id, plugin_name FROM plugins',
         pos_in_log    => 412,
         bytes         => 42,
         cmd           => 'Query',
         Query_time    => '0.002161',
      },
   ],
);

# A log with informational messages.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-log-007.txt',
   result => [
      {  arg           => 'SELECT plugin_id, plugin_name FROM plugins',
         pos_in_log    => 20,
         bytes         => 42,
         cmd           => 'Query',
         Query_time    => '0.002991',
      },
   ],
);

# Test that meta-data in connection/disconnnection lines is captured.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-log-008.txt',
   result => [
      {  ts            => '2010-02-08 15:31:48',
         host          => '[local]',
         arg           => 'connection received',
         pos_in_log    => 0,
         bytes         => 19,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-08 15:31:48',
         user          => 'fred',
         db            => 'fred',
         arg           => 'connection authorized',
         pos_in_log    => 64,
         bytes         => 21,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-08 15:32:06',
         db            => 'fred',
         user          => 'fred',
         host          => '[local]',
         arg           => 'disconnection',
         pos_in_log    => 141,
         bytes         => length('disconnection'),
         cmd           => 'Admin',
      },
   ],
);

# Simple sample of syslog output.  It has a complexity: there is a trailing
# orphaned duration line, which can appear to be for the statement -- but isn't.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-syslog-001.txt',
   result => [
      {  pos_in_log    => 0,
         bytes         => 1193,
         cmd           => 'Query',
         Query_time    => '3.617465',
         arg           => "select t.tid,t.title,m.name,gn.name,to_char( t.retail_reldate, 'mm-dd-yy' ) as retail_reldate,coalesce(s0c100r0.units,0) as"
                           ." w0c100r0units,'NA' as w0c100r0dollars,'NA' as w0c100r0arp,coalesce(s0c1r0.units,0) as w0c1r0units,'NA' as w0c1r0dollars,'NA' as"
                           ." w0c1r0arp,coalesce(s0c2r0.units,0) as w0c2r0units,coalesce(s0c2r0.dollars,0) as w0c2r0dollars,arp(s0c2r0.dollars, s0c2r0.units)"
                           ." as w0c2r0arp from title t left outer join sublabel sl on t.sublabel_rel = sl.key left outer join label s on sl.lid = s.id left"
                           ." outer join label d on s.did = d.id left outer join sale_200601 s0c100r0 on t.tid = s0c100r0.tid and s0c100r0.week = 200601 and"
                           ." s0c100r0.channel = 100 and s0c100r0.region = 0 left outer join sale_200601 s0c1r0 on t.tid = s0c1r0.tid and s0c1r0.week ="
                           ." 200601 and s0c1r0.channel = 1 and s0c1r0.region = 0 left outer join sale_200601 s0c2r0 on t.tid = s0c2r0.tid and s0c2r0.week ="
                           ." 200601 and s0c2r0.channel = 2 and s0c2r0.region = 0 left outer join media m on t.media = m.key left outer join genre_n gn on"
                           ." t.genre_n = gn.key where ((((upper(t.title) like '%MATRIX%' or upper(t.artist) like '%MATRIX%') ))) and t.blob in ('L', 'M',"
                           ." 'R') and t.source_dvd != 'IN' order by t.title asc limit 100",
      },
   ],
);

# Syslog output with a query that has an error.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-syslog-002.txt',
   result => [
      {  ts            => '2010-02-08 09:52:41.526',
         pos_in_log    => 0,
         bytes         => 31,
         cmd           => 'Query',
         Query_time    => '0.008309',
         arg           => "select * from pg_stat_bgwriter;",
         db            => 'fred',
         user          => 'fred',
         Session_id    => '4b701056.1dc6',
      },
      {  ts            => '2010-02-08 09:52:57.807',
         pos_in_log    => 282,
         bytes         => 29,
         cmd           => 'Query',
         arg           => "create index ix_a on foo (a);",
         Error_msg     => 'relation "ix_a" already exists',
         db            => 'fred',
         user          => 'fred',
         Session_id    => '4b701056.1dc6',
      },
   ],
);

# Syslog output with a query that has newlines *and* a query line that's too
# long and is broken across 2 lines in the log.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-syslog-003.txt',
   result => [
      {  ts            => '2010-02-08 09:53:51.724',
         pos_in_log    => 0,
         bytes         => 526,
         cmd           => 'Query',
         Query_time    => '0.150472',
         arg           => "SELECT n.nspname as \"Schema\","
                         . "\n  c.relname as \"Name\","
                         . "\n  CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'i' THEN 'index' WHEN 'S' THEN 'sequence' WHEN 's' THEN"
                         . " 'special' END as \"Type\","
                         . "\n  r.rolname as \"Owner\""
                         . "\nFROM pg_catalog.pg_class c"
                         . "\n     JOIN pg_catalog.pg_roles r ON r.oid = c.relowner"
                         . "\n     LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace"
                         . "\nWHERE c.relkind IN ('r','v','S','')"
                         . "\n  AND n.nspname <> 'pg_catalog'"
                         . "\n  AND n.nspname !~ '^pg_toast'"
                         . "\n  AND pg_catalog.pg_table_is_visible(c.oid)"
                         . "\nORDER BY 1,2;",
         db            => 'fred',
         user          => 'fred',
         Session_id    => '4b701056.1dc6',
      },
   ],
);

# Syslog output with a query that has newlines with tabs translated to ^I
# characters.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-syslog-004.txt',
   result => [
      {  pos_in_log    => 0,
         bytes         => 357,
         cmd           => 'Query',
         arg           => "SELECT groups.group_name,groups.unix_group_name,"
                        . "\n\tgroups.type,users.user_name,users.realname,"
                        . "\n\tnews_bytes.forum_id,news_bytes.summary,news_bytes.date,news_bytes.details "
                        . "\n\tFROM users,news_bytes,groups "
                        . "\n\tWHERE news_bytes.is_approved=1 "
                        . "\n\tAND users.user_id=news_bytes.submitted_by "
                        . "\n\tAND news_bytes.group_id=groups.group_id "
                        . "\n\tORDER BY date DESC LIMIT 10 OFFSET 0",
      },
   ],
);

# This is basically the same as t/lib/samples/pg/pg-log-001.txt but it's in
# syslog format.  It's interesting and complicated because the disconnect
# message is broken across two lines in the file by syslog, although this would
# not be done in PostgreSQL's own logging format.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-syslog-005.txt',
   result => [
      {  ts            => '2010-02-10 09:03:26.918',
         host          => '[local]',
         db            => '[unknown]',
         user          => '[unknown]',
         arg           => 'connection received',
         Session_id    => '4b72bcae.d01',
         pos_in_log    => 0,
         bytes         => 19,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-10 09:03:26.922',
         user          => 'fred',
         db            => 'fred',
         arg           => 'connection authorized',
         Session_id    => '4b72bcae.d01',
         pos_in_log    => 152,
         bytes         => 21,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-10 09:03:36.645',
         db            => 'fred',
         user          => 'fred',
         arg           => 'select 1;',
         Query_time    => '0.000627',
         Session_id    => '4b72bcae.d01',
         pos_in_log    => 307,
         bytes         => length('select 1;'),
         cmd           => 'Query',
      },
      {  ts            => '2010-02-10 09:03:39.075',
         db            => 'fred',
         user          => 'fred',
         host          => '[local]',
         arg           => 'disconnection',
         Session_id    => '4b72bcae.d01',
         pos_in_log    => 456,
         bytes         => length('disconnection'),
         cmd           => 'Admin',
      },
   ],
);

# This is interesting because it has a mix of lines that are genuinely broken
# with a newline, and thus start with ^I; and lines that are broken by syslog
# for being too long.  It has a line that's just too long and is broken in a
# place there's no space, which is unusual.  It also starts and ends with a
# newline, so it's a good test of whether chomping/trimming is done right.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-syslog-006.txt',
   result => [
      {  pos_in_log    => 0,
         bytes         => 657,
         cmd           => 'Query',
         Query_time    => '0.117042',
         arg           => "\ninsert into weblog"
                        . " (username,remoteid,generalsitearea,refererhost,refererfull,searchterms,cookie,useragent,query,requesteduri,bot,elapsedtime)"
                        . "\nvalues"
                        . " (upper('asdfg'),upper('127.0.0.1'),upper(NULL),upper('localhost'),upper('<a href=\"http://localhost/nosymbol-Ameriprise-Financial-Inc-Fun\" target=\"_new\">http://localhost/nosymbol-Ameriprise-Financial-Inc-Fun</a>"
                        . "d-Buy-Sell-Own-zz-zi125340.html'),upper(NULL),upper('temp-id=s2ByrI6TKLEoDJXG3g3NEBoRWF6Z3t'),upper('Mozilla/4.0 (compatible;"
                        . " MSIE 7.0; Windows NT 5.2; .NET CLR 1.1.4322; .NET CLR 2.0.50727; .NET CLR"
                        . " 3.0.04506.30)'),upper(''),upper('/AAON-Aaon-Inc-Stock-Buy-Sell-Own-zz-zs2331501.html'),'f','1')"
                        . "\n"
      },
   ],
);

# This file has a few different things in it: embedded newline in a string, long
# non-broken strings, ERROR line that doesn't describe the previous line but
# rather is followed by a STATEMENT line.
test_log_parser(
   parser => $p,
   file   => 't/lib/samples/pg/pg-syslog-007.txt',
   result => [
      {  Query_time => '0.039219',
         Session_id => '12345',
         arg =>
            "select 'a very long sentence a very long sentence a very long "
            . "sentence a very long sentence a very long sentence a very "
            . "long sentence a very long sentence ;\n';",
         bytes      => 159,
         cmd        => 'Query',
         db         => 'fred',
         pos_in_log => 0,
         ts         => '2010-02-12 06:00:54.566',
         user       => 'fred'
      },
      {  Query_time => '0.000589',
         Session_id => '12345',
         arg =>
            "select 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            . "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            . "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            . "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            . "aaaaaaaaaaaaaaaaaaaaaaaa';",
         bytes      => 280,
         cmd        => 'Query',
         db         => 'fred',
         pos_in_log => '388',
         ts         => '2010-02-12 06:01:09.854',
         user       => 'fred',
      },
      {
         Query_time => '0.000556',
         Session_id => '12345',
         arg        => "select '\nhello';",
         bytes      => 16,
         cmd        => 'Query',
         db         => 'fred',
         pos_in_log => '939',
         ts         => '2010-02-12 06:01:22.860',
         user       => 'fred'
      },
      {  Error_msg  => 'unrecognized configuration parameter "foobar"',
         Session_id => '12345',
         arg        => "show foobar;",
         bytes      => length('show foobar;'),
         cmd        => 'Query',
         db         => 'fred',
         pos_in_log => '1139',
         ts         => '2010-02-12 06:03:14.307',
         user       => 'fred',
      },
   ],
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $p->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
