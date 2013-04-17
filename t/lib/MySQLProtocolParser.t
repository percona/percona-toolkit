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

use ProtocolParser;
use MySQLProtocolParser;
use TcpdumpParser;
use PerconaTest;

my $sample  = "t/lib/samples/tcpdump";
my $tcpdump = new TcpdumpParser();
my $protocol; # Create a new MySQLProtocolParser for each test.

# Check that I can parse a really simple session.
$protocol = new MySQLProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump001.txt",
   result   => [
      {  ts            => '090412 09:50:16.805123',
         db            => undef,
         user          => undef,
         Thread_id     => 4294967296,
         host          => '127.0.0.1',
         ip            => '127.0.0.1',
         port          => '42167',
         arg           => 'select "hello world" as greeting',
         Query_time    => sprintf('%.6f', .805123 - .804849),
         pos_in_log    => 0,
         bytes         => length('select "hello world" as greeting'),
         cmd           => 'Query',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
);

# A more complex session with a complete login/logout cycle.
$protocol = new MySQLProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump002.txt",
   result   => [
      {  ts         => "090412 11:00:13.118191",
         db         => 'mysql',
         user       => 'msandbox',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '57890',
         arg        => 'administrator command: Connect',
         Query_time => '0.011152',
         Thread_id  => 8,
         pos_in_log => 1470,
         bytes      => length('administrator command: Connect'),
         cmd        => 'Admin',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
      {  Query_time => '0.000265',
         Thread_id  => 8,
         arg        => 'select @@version_comment limit 1',
         bytes      => length('select @@version_comment limit 1'),
         cmd        => 'Query',
         db         => 'mysql',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '57890',
         pos_in_log => 2449,
         ts         => '090412 11:00:13.118643',
         user       => 'msandbox',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
      {  Query_time => '0.000167',
         Thread_id  => 8,
         arg        => 'select "paris in the the spring" as trick',
         bytes      => length('select "paris in the the spring" as trick'),
         cmd        => 'Query',
         db         => 'mysql',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '57890',
         pos_in_log => 3298,
         ts         => '090412 11:00:13.119079',
         user       => 'msandbox',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
      {  Query_time => '0.000000',
         Thread_id  => 8,
         arg        => 'administrator command: Quit',
         bytes      => 27,
         cmd        => 'Admin',
         db         => 'mysql',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '57890',
         pos_in_log => '4186',
         ts         => '090412 11:00:13.119487',
         user       => 'msandbox',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
);

# A session that has an error during login.
$protocol = new MySQLProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump003.txt",
   result   => [
      {  ts         => "090412 12:41:46.357853",
         db         => '',
         user       => 'msandbox',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '44488',
         arg        => 'administrator command: Connect',
         Query_time => '0.010753',
         Thread_id  => 9,
         pos_in_log => 1455,
         bytes      => length('administrator command: Connect'),
         cmd        => 'Admin',
         Error_no   => 1045,
         Error_msg  => 'Access denied for user \'msandbox\'@\'localhost\' (using password: YES)',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
);

# A session that has an error executing a query
$protocol = new MySQLProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump004.txt",
   result   => [
      {  ts         => "090412 12:58:02.036002",
         db         => undef,
         user       => undef,
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '60439',
         arg        => 'select 5 from foo',
         Query_time => '0.000251',
         Thread_id  => 4294967296,
         pos_in_log => 0,
         bytes      => length('select 5 from foo'),
         cmd        => 'Query',
         Error_no   => "1046",
         Error_msg  => 'No database selected',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
);

# A session that has a single-row insert and a multi-row insert
$protocol = new MySQLProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump005.txt",
   result   => [
      {
         Rows_affected => 1,
         Query_time => '0.000435',
         Thread_id  => 4294967296,
         arg        => 'insert into test.t values(1)',
         bytes      => 28,
         cmd        => 'Query',
         db         => undef,
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '55300',
         pos_in_log => '0',
         ts         => '090412 16:46:02.978340',
         user       => undef,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
      {
         Rows_affected => 2,
         Query_time => '0.000565',
         Thread_id  => 4294967296,
         arg        => 'insert into test.t values(1),(2)',
         bytes      => 32,
         cmd        => 'Query',
         db         => undef,
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '55300',
         pos_in_log => '1033',
         ts         => '090412 16:46:20.245088',
         user       => undef,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
);

# A session that causes a slow query because it doesn't use an index.
$protocol = new MySQLProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump006.txt",
   result   => [
      {  ts         => '100412 20:46:10.776899',
         db         => undef,
         user       => undef,
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '48259',
         arg        => 'select * from t',
         Query_time => '0.000205',
         Thread_id  => 4294967296,
         pos_in_log => 0,
         bytes      => length('select * from t'),
         cmd        => 'Query',
         Rows_affected      => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'Yes',
      },
   ],
);

# A session that truncates an insert.
$protocol = new MySQLProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump007.txt",
   result   => [
      {  ts         => '090412 20:57:22.798296',
         db         => undef,
         user       => undef,
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '38381',
         arg        => 'insert into t values(current_date)',
         Query_time => '0.000020',
         Thread_id  => 4294967296,
         pos_in_log => 0,
         bytes      => length('insert into t values(current_date)'),
         cmd        => 'Query',
         Rows_affected      => 1,
         Warning_count      => 1,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
);

# #############################################################################
# Check the individual packet parsing subs.
# #############################################################################
 
is_deeply(
   MySQLProtocolParser::parse_error_packet(load_data("t/lib/samples/mysql_proto_001.txt")),
   {
      errno    => '1046',
      sqlstate => '#3D000',
      message  => 'No database selected',
   },
   'Parse error packet'
);

is_deeply(
   MySQLProtocolParser::parse_ok_packet('010002000100'),
   {
      affected_rows => 1,
      insert_id     => 0,
      status        => 2,
      warnings      => 1,
      message       => '',
   },
   'Parse ok packet'
);

is_deeply(
   MySQLProtocolParser::parse_server_handshake_packet(load_data("t/lib/samples/mysql_proto_002.txt")),
   {
      thread_id      => '9',
      server_version => '5.0.67-0ubuntu6-log',
      flags          => {
         CLIENT_COMPRESS          => 1,
         CLIENT_CONNECT_WITH_DB   => 1,
         CLIENT_FOUND_ROWS        => 0,
         CLIENT_IGNORE_SIGPIPE    => 0,
         CLIENT_IGNORE_SPACE      => 0,
         CLIENT_INTERACTIVE       => 0,
         CLIENT_LOCAL_FILES       => 0,
         CLIENT_LONG_FLAG         => 1,
         CLIENT_LONG_PASSWORD     => 0,
         CLIENT_MULTI_RESULTS     => 0,
         CLIENT_MULTI_STATEMENTS  => 0,
         CLIENT_NO_SCHEMA         => 0,
         CLIENT_ODBC              => 0,
         CLIENT_PROTOCOL_41       => 1,
         CLIENT_RESERVED          => 0,
         CLIENT_SECURE_CONNECTION => 1,
         CLIENT_SSL               => 0,
         CLIENT_TRANSACTIONS      => 1,
      }
   },
   'Parse server handshake packet'
);

is_deeply(
   MySQLProtocolParser::parse_client_handshake_packet(load_data("t/lib/samples/mysql_proto_003.txt")),
   {
      db    => 'mysql',
      user  => 'msandbox',
      flags => {
         CLIENT_COMPRESS          => 0,
         CLIENT_CONNECT_WITH_DB   => 1,
         CLIENT_FOUND_ROWS        => 0,
         CLIENT_IGNORE_SIGPIPE    => 0,
         CLIENT_IGNORE_SPACE      => 0,
         CLIENT_INTERACTIVE       => 0,
         CLIENT_LOCAL_FILES       => 1,
         CLIENT_LONG_FLAG         => 1,
         CLIENT_LONG_PASSWORD     => 1,
         CLIENT_MULTI_RESULTS     => 1,
         CLIENT_MULTI_STATEMENTS  => 1,
         CLIENT_NO_SCHEMA         => 0,
         CLIENT_ODBC              => 0,
         CLIENT_PROTOCOL_41       => 1,
         CLIENT_RESERVED          => 0,
         CLIENT_SECURE_CONNECTION => 1,
         CLIENT_SSL               => 0,
         CLIENT_TRANSACTIONS      => 1,
      },
   },
   'Parse client handshake packet'
);

is_deeply(
   MySQLProtocolParser::parse_com_packet('0373686f77207761726e696e67738d2dacbc', 14),
   {
      code => '03',
      com  => 'COM_QUERY',
      data => 'show warnings',
   },
   'Parse COM_QUERY packet'
);

# Test that we can parse with a non-standard port etc.
$protocol = new MySQLProtocolParser(
   server => '192.168.1.1',
   port   => '3307',
);
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump012.txt",
   result   => [
      {  ts            => '090412 09:50:16.805123',
         db            => undef,
         user          => undef,
         Thread_id     => 4294967296,
         host          => '127.0.0.1',
         ip            => '127.0.0.1',
         port          => '42167',
         arg           => 'select "hello world" as greeting',
         Query_time    => sprintf('%.6f', .805123 - .804849),
         pos_in_log    => 0,
         bytes         => length('select "hello world" as greeting'),
         cmd           => 'Query',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
);

# #############################################################################
# Issue 447: MySQLProtocolParser does not handle old password algo or
# compressed packets  
# #############################################################################
$protocol = new MySQLProtocolParser(
   server => '10.55.200.15',
);
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump013.txt",
   desc     => 'old password and compression',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.034355',
         Rows_affected => 0,
         Thread_id => 36947020,
         Warning_count => 0,
         arg => 'administrator command: Connect',
         bytes => 30,
         cmd => 'Admin',
         db => '',
         host => '10.54.212.171',
         ip => '10.54.212.171',
         port => '49663',
         pos_in_log => 1834,
         ts => '090603 10:52:24.578817',
         user => 'luck'
      },
   ],
);

# Check in-stream compression detection.
$protocol = new MySQLProtocolParser(
   server => '10.55.200.15',
);
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump014.txt",
   desc     => 'in-stream compression detection',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used      => 'No',
         Query_time         => '0.001375',
         Rows_affected      => 0,
         Thread_id          => 4294967296,
         Warning_count      => 0,
         arg                => 'show databases',
         bytes              => 14,
         cmd                => 'Query',
         db                 => undef,
         host               => '10.54.212.171',
         ip                 => '10.54.212.171',
         port               => '49663',
         pos_in_log         => 0,
         ts                 => '090603 10:52:24.587685',
         user               => undef,
      },
   ],
);

eval { require IO::Uncompress::Inflate; };
SKIP: {
   skip "IO::Uncompress::Inflate not installed", 2 if $EVAL_ERROR;

   # Check data decompression.
   $protocol = new MySQLProtocolParser(
      server => '127.0.0.1',
      port   => '12345',
   );
   test_protocol_parser(
      parser   => $tcpdump,
      protocol => $protocol,
      file     => "$sample/tcpdump015.txt",
      desc     => 'compressed data',
      result   => [
         {
            No_good_index_used => 'No',
            No_index_used => 'No',
            Query_time => '0.006415',
            Rows_affected => 0,
            Thread_id => 20,
            Warning_count => 0,
            arg => 'administrator command: Connect',
            bytes => 30,
            cmd => 'Admin',
            db => 'mysql',
            host => '127.0.0.1',
            ip => '127.0.0.1',
            port => '44489',
            pos_in_log => 664,
            ts => '090612 08:39:05.316805',
            user => 'msandbox',
         },
         {
            No_good_index_used => 'No',
            No_index_used => 'Yes',
            Query_time => '0.002884',
            Rows_affected => 0,
            Thread_id => 20,
            Warning_count => 0,
            arg => 'select * from help_relation',
            bytes => 27,
            cmd => 'Query',
            db => 'mysql',
            host => '127.0.0.1',
            ip => '127.0.0.1',
            port => '44489',
            pos_in_log => 1637,
            ts => '090612 08:39:08.428913',
            user => 'msandbox',
         },
         {
            No_good_index_used => 'No',
            No_index_used => 'No',
            Query_time => '0.000000',
            Rows_affected => 0,
            Thread_id => 20,
            Warning_count => 0,
            arg => 'administrator command: Quit',
            bytes => 27,
            cmd => 'Admin',
            db => 'mysql',
            host => '127.0.0.1',
            ip => '127.0.0.1',
            port => '44489',
            pos_in_log => 15782,
            ts => '090612 08:39:09.145334',
            user => 'msandbox',
         },
      ],
   );
}

# TCP retransmission.
$protocol = new MySQLProtocolParser(
   server => '10.55.200.15',
);
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump016.txt",
   desc     => 'TCP retransmission',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.001000',
         Rows_affected => 0,
         Thread_id => 38559282,
         Warning_count => 0,
         arg => 'administrator command: Connect',
         bytes => 30,
         cmd => 'Admin',
         db => '',
         host => '10.55.200.31',
         ip => '10.55.200.31',
         port => '64987',
         pos_in_log => 468,
         ts => '090609 16:53:17.112346',
         user => 'ppppadri',
      },
   ],
);

# #############################################################################
# Issue 537: MySQLProtocolParser and MemcachedProtocolParser do not handle
# multiple servers.
# #############################################################################
$protocol = new MySQLProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump018.txt",
   desc     => 'Multiple servers',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000206',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'select * from foo',
         bytes => 17,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '42275',
         pos_in_log => 0,
         ts => '090727 08:28:41.723651',
         user => undef,
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000203',
         Rows_affected => 0,
         Thread_id => '4294967297',
         Warning_count => 0,
         arg => 'select * from bar',
         bytes => 17,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '34233',
         pos_in_log => 987,
         ts => '090727 08:29:34.232748',
         user => undef,
      },
   ],
);

# Test that --watch-server causes just the given server to be watched.
$protocol = new MySQLProtocolParser(server=>'10.0.0.1',port=>'3306');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump018.txt",
   desc     => 'Multiple servers but watch only one',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000206',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'select * from foo',
         bytes => 17,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '42275',
         pos_in_log => 0,
         ts => '090727 08:28:41.723651',
         user => undef,
      },
   ]
);


# #############################################################################
# Issue 558: Make mk-query-digest handle big/fragmented packets
# #############################################################################
$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'12345');
my $e = test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump019.txt",
);

like(
   $e->[0]->{arg},
   qr/--THE END--'\)$/,
   'Handles big, fragmented MySQL packets (issue 558)'
);

my $arg = load_file("$sample/tcpdump019-arg.txt");
chomp $arg;
is(
   $e->[0]->{arg},
   $arg,
   'Re-assembled data is correct (issue 558)'
);

# #############################################################################
# Issue 740: Handle prepared statements
# #############################################################################
$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'12345');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump021.txt",
   desc     => 'prepared statements, simple, no NULL',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000286',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT i FROM d.t WHERE i=?',
         bytes => 35,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '58619',
         pos_in_log => 0,
         ts => '091208 09:23:49.637394',
         user => undef,
         Statement_id => 2,
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'Yes',
         Query_time => '0.000281',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'EXECUTE SELECT i FROM d.t WHERE i="3"',
         bytes => 37,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '58619',
         pos_in_log => 1106,
         ts => '091208 09:23:49.637892',
         user => undef,
         Statement_id => 2,
      },
      {
          No_good_index_used => 'No',
          No_index_used => 'No',
          Query_time => '0.000000',
          Rows_affected => 0,
          Thread_id => '4294967296',
          Warning_count => 0,
          arg => 'administrator command: Quit',
          bytes => 27,
          cmd => 'Admin',
          db => undef,
          host => '127.0.0.1',
          ip => '127.0.0.1',
          port => '58619',
          pos_in_log => 1850,
          ts => '091208 09:23:49.638381',
          user => undef
      },
   ],
);

$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'12345');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump022.txt",
   desc     => 'prepared statements, NULL value',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000303',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT i,j FROM d.t2 WHERE i=? AND j=?',
         bytes => 46,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '44545',
         pos_in_log => 0,
         ts => '091208 13:41:12.811188',
         user => undef,
         Statement_id => 2,
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000186',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'EXECUTE SELECT i,j FROM d.t2 WHERE i=NULL AND j="5"',
         bytes => 51,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '44545',
         pos_in_log => 1330,
         ts => '091208 13:41:12.811591',
         user => undef,
         Statement_id => 2,
      }
   ],
);

$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'12345');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump023.txt",
   desc     => 'prepared statements, string, char and float',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000315',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT * FROM d.t3 WHERE v=? OR c=? OR f=?',
         bytes => 50,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '49806',
         pos_in_log => 0,
         ts => '091208 14:14:55.951863',
         user => undef,
         Statement_id => 2,
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000249',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'EXECUTE SELECT * FROM d.t3 WHERE v="hello world" OR c="a" OR f="1.23"',
         bytes => 69,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '49806',
         pos_in_log => 1540,
         ts => '091208 14:14:55.952344',
         user => undef,
         Statement_id => 2,
      }
   ],
);

$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'12345');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump024.txt",
   desc     => 'prepared statements, all NULL',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000278',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT * FROM d.t3 WHERE v=? OR c=? OR f=?',
         bytes => 50,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '32810',
         pos_in_log => 0,
         ts => '091208 14:33:13.711351',
         user => undef,
         Statement_id => 2,
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000159',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'EXECUTE SELECT * FROM d.t3 WHERE v=NULL OR c=NULL OR f=NULL',
         bytes => 59,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '32810',
         pos_in_log => 1540,
         ts => '091208 14:33:13.711642',
         user => undef,
         Statement_id => 2,
      },
   ],
);

$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'12345');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump025.txt",
   desc     => 'prepared statements, no params',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000268',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT * FROM d.t WHERE 1 LIMIT 1;',
         bytes => 42,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '48585',
         pos_in_log => 0,
         ts => '091208 14:44:52.709181',
         user => undef,
         Statement_id => 2,
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'Yes',
         Query_time => '0.000234',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'EXECUTE SELECT * FROM d.t WHERE 1 LIMIT 1;',
         bytes => 42,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '48585',
         pos_in_log => 1014,
         ts => '091208 14:44:52.709597',
         user => undef,
         Statement_id => 2,
      }
   ],
);

$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'3306');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump026.txt",
   desc     => 'prepared statements, close statement',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000000',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'DEALLOCATE PREPARE 50',
         bytes => 21,
         cmd => 'Query',
         db => undef,
         host => '1.2.3.4',
         ip => '1.2.3.4',
         port => '34162',
         pos_in_log => 0,
         ts => '091208 17:42:12.696547',
         user => undef
      }
   ],
);

$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'3306');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump027.txt",
   desc     => 'prepared statements, reset statement',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000023',
         Rows_affected => 0,
         Statement_id => 51,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'RESET 51',
         bytes => 8,
         cmd => 'Query',
         db => undef,
         host => '1.2.3.4',
         ip => '1.2.3.4',
         port => '34162',
         pos_in_log => 0,
         ts => '091208 17:42:12.698093',
         user => undef
      }
   ],
);

$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'12345');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump028.txt",
   desc     => 'prepared statements, multiple exec, new param',
   result => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000292',
         Rows_affected => 0,
         Statement_id => 2,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT * FROM d.t WHERE i=?',
         bytes => 35,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '38682',
         pos_in_log => 0,
         ts => '091208 17:35:37.433248',
         user => undef
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'Yes',
         Query_time => '0.000254',
         Rows_affected => 0,
         Statement_id => 2,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'EXECUTE SELECT * FROM d.t WHERE i="1"',
         bytes => 37,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '38682',
         pos_in_log => 1106,
         ts => '091208 17:35:37.433700',
         user => undef
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'Yes',
         Query_time => '0.000190',
         Rows_affected => 0,
         Statement_id => 2,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'EXECUTE SELECT * FROM d.t WHERE i="3"',
         bytes => 37,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '38682',
         pos_in_log => 1850,
         ts => '091208 17:35:37.434303',
         user => undef
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'Yes',
         Query_time => '0.000166',
         Rows_affected => 0,
         Statement_id => 2,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'EXECUTE SELECT * FROM d.t WHERE i=NULL',
         bytes => 38,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '38682',
         pos_in_log => 2589,
         ts => '091208 17:35:37.434708',
         user => undef
      }
   ],
);

$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'12345');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump029.txt",
   desc     => 'prepared statements, real param types',
   result => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000221',
         Rows_affected => 0,
         Statement_id => 1,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT * FROM d.t WHERE i=? OR u=? OR v=? OR d=? OR f=? OR t > ? OR dt > ?',
         bytes => 82,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '36496',
         pos_in_log => 0,
         ts => '091209 09:20:59.293775',
         user => undef
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000203',
         Rows_affected => 0,
         Statement_id => 1,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'EXECUTE SELECT * FROM d.t WHERE i=42 OR u=2009 OR v="hello world" OR d=1.23 OR f=4.56 OR t > "2009-12-01" OR dt > "2009-12-01"',
         bytes => 126,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '36496',
         pos_in_log => 2109,
         ts => '091209 09:20:59.294409',
         user => undef
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000000',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'DEALLOCATE PREPARE 1',
         bytes => 20,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '36496',
         pos_in_log => 3787,
         ts => '091209 09:20:59.294926',
         user => undef
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000000',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'administrator command: Quit',
         bytes => 27,
         cmd => 'Admin',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '36496',
         pos_in_log => 4051,
         ts => '091209 09:20:59.295064',
         user => undef
      },
   ]
);

$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'3306');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump030.txt",
   desc     => 'prepared statements, ok response to execute',
   result => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000046',
         Rows_affected => 0,
         Statement_id => 1,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SET SESSION sql_mode="STRICT_ALL_TABLES"',
         bytes => 48,
         cmd => 'Query',
         db => undef,
         host => '1.2.3.24',
         ip => '1.2.3.24',
         port => '60696',
         pos_in_log => 0,
         ts => '091210 14:21:16.956302',
         user => undef
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000024',
         Rows_affected => 0,
         Statement_id => 1,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'EXECUTE SET SESSION sql_mode="STRICT_ALL_TABLES"',
         bytes => 48,
         cmd => 'Query',
         db => undef,
         host => '1.2.3.24',
         ip => '1.2.3.24',
         port => '60696',
         pos_in_log => 700,
         ts => '091210 14:21:16.956446',
         user => undef
      }
   ],
);

$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'3306');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump034.txt",
   desc     => 'prepared statements, NULL bitmap',
   result => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000288',
         Rows_affected => 0,
         Statement_id => 1,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT * FROM d.t WHERE i=? OR u=? OR v=? OR d=? OR f=? OR t > ? OR dt > ? OR i2=? OR i3=? OR i4=?',
         bytes => 106,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '43607',
         pos_in_log => 0,
         ts => '091224 16:47:24.204501',
         user => undef
      },
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000322',
         Rows_affected => 0,
         Statement_id => 1,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'EXECUTE SELECT * FROM d.t WHERE i=42 OR u=2009 OR v="hello world" OR d=1.23 OR f=4.56 OR t > "2009-12-01" OR dt > "2009-12-01" OR i2=NULL OR i3=NULL OR i4=NULL',
         bytes => 159,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '43607',
         pos_in_log => 2748,
         ts => '091224 16:47:24.204965',
         user => undef
      }
   ],
);

# #############################################################################
# Issue 761: mk-query-digest --tcpdump does not handle incomplete packets
# #############################################################################
$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'3306');
$protocol->{_no_save_error} = 1;
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump032.txt",
   desc     => 'issue 761',
   result => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000431',
         Rows_affected => 1,
         Thread_id => '4294967296',
         Warning_count => 21032,
         arg => 'UPDATEDDDDNNNN',
         bytes => 14,
         cmd => 'Query',
         db => undef,
         host => '1.2.3.4',
         ip => '1.2.3.4',
         port => '35957',
         pos_in_log => 1768,
         ts => '091208 20:54:54.795250',
         user => undef
      }
   ],
);

# #############################################################################
# Issue 760: mk-query-digest --tcpdump might not get the whole query
# #############################################################################
$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'3306');
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump031.txt",
   desc     => 'issue 760',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000430',
         Rows_affected => 1,
         Thread_id => '4294967296',
         Warning_count => 21032,
         arg => 'UPDATEDDDDNNNN',
         bytes => 14,
         cmd => 'Query',
         db => undef,
         host => '1.2.3.4',
         ip => '1.2.3.4',
         port => '35957',
         pos_in_log => 534,
         ts => '091207 20:54:54.795250',
         user => undef
      }
   ],
);

# #############################################################################
# Issue 794: MySQLProtocolParser does not handle client port reuse
# #############################################################################
$protocol = new MySQLProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump035.txt",
   desc     => 'client port reuse (issue 794)',
   result   => [
      {  ts         => "090412 11:00:13.118191",
         db         => 'mysql',
         user       => 'msandbox',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '57890',
         arg        => 'administrator command: Connect',
         Query_time => '0.011152',
         Thread_id  => 8,
         pos_in_log => 1470,
         bytes      => length('administrator command: Connect'),
         cmd        => 'Admin',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
      {  Query_time => '0.000167',
         Thread_id  => 8,
         arg        => 'select "paris in the the spring" as trick',
         bytes      => length('select "paris in the the spring" as trick'),
         cmd        => 'Query',
         db         => 'mysql',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '57890',
         pos_in_log => 2449,
         ts         => '090412 11:00:13.119079',
         user       => 'msandbox',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
      {  Query_time => '0.000000',
         Thread_id  => 8,
         arg        => 'administrator command: Quit',
         bytes      => 27,
         cmd        => 'Admin',
         db         => 'mysql',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '57890',
         pos_in_log => 3337,
         ts         => '090412 11:00:13.119487',
         user       => 'msandbox',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
      # port reused...      
      {  ts => '090412 12:00:00.800000',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.700000',
         Rows_affected => 0,
         Thread_id => 8,
         Warning_count => 0,
         arg => 'administrator command: Connect',
         bytes => 30,
         cmd => 'Admin',
         db => 'mysql',
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '57890',
         pos_in_log => 5791,
         user => 'msandbox',
      },
      {  ts => '090412 12:00:01.000000',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.100000',
         Rows_affected => 0,
         Thread_id => 8,
         Warning_count => 0,
         arg => 'select "paris in the the spring" as trick',
         bytes => 41,
         cmd => 'Query',
         db => 'mysql',
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '57890',
         pos_in_log => 6770, 
         user => 'msandbox',
      },
      {  ts => '090412 12:00:01.100000',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000000',
         Rows_affected => 0,
         Thread_id => 8,
         Warning_count => 0,
         arg => 'administrator command: Quit',
         bytes => 27,
         cmd => 'Admin',
         db => 'mysql',
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '57890',
         pos_in_log => 7658,
         user => 'msandbox',
      }
   ],
);

$protocol = new MySQLProtocolParser();
$protocol->{_no_save_error} = 1;
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump036.txt",
   desc     => 'Houdini data (issue 794)',
   result   => [
      {  ts         => "090412 11:00:13.118191",
         db         => 'mysql',
         user       => 'msandbox',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '57890',
         arg        => 'administrator command: Connect',
         Query_time => '0.011152',
         Thread_id  => 8,
         pos_in_log => 1470,
         bytes      => length('administrator command: Connect'),
         cmd        => 'Admin',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
      # port reused...      
      {  ts => '090412 12:00:00.800000',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.700000',
         Rows_affected => 0,
         Thread_id => 8,
         Warning_count => 0,
         arg => 'administrator command: Connect',
         bytes => 30,
         cmd => 'Admin',
         db => 'mysql',
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '57890',
         pos_in_log => 4161,
         user => 'msandbox',
      },
      {  ts => '090412 12:00:01.000000',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.100000',
         Rows_affected => 0,
         Thread_id => 8,
         Warning_count => 0,
         arg => 'select "paris in the the spring" as trick',
         bytes => 41,
         cmd => 'Query',
         db => 'mysql',
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '57890',
         pos_in_log => 5140,
         user => 'msandbox',
      },
      {  ts => '090412 12:00:01.100000',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000000',
         Rows_affected => 0,
         Thread_id => 8,
         Warning_count => 0,
         arg => 'administrator command: Quit',
         bytes => 27,
         cmd => 'Admin',
         db => 'mysql',
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '57890',
         pos_in_log => 6028,
         user => 'msandbox',
      }
   ],
);

$protocol = new MySQLProtocolParser();
$protocol->{_no_save_error} = 1;
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump037.txt",
   desc     => 'no server ok (issue 794)',
   result   => [
      {  ts => '090412 12:00:01.000000',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000000',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'administrator command: Quit',
         bytes => 27,
         cmd => 'Admin',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '57890',
         pos_in_log => 390,
         user => undef
      },
      {  ts => '090412 12:00:03.000000',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '1.000000',
         Rows_affected => 0,
         Thread_id => 4294967297,
         Warning_count => 0,
         arg => 'select "paris in the the spring" as trick',
         bytes => 41,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '57890',
         pos_in_log => 646,
         user => undef,
      },
   ],
);

# #############################################################################
# Issue 832: mk-query-digest tcpdump crashes on successive, fragmented
# client query
# #############################################################################
$protocol = new MySQLProtocolParser(server => '127.0.0.1',port=>'12345');
$protocol->{_no_save_error} = 1;
$e = test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump038.txt",
);

like(
   $e->[0]->{arg},
   qr/--THE END--'\)$/,
   '2nd, fragmented client query (issue 832)',
);

# #############################################################################
# Issue 670: Make mk-query-digest capture the error message from tcpdump
# #############################################################################
$protocol = new MySQLProtocolParser(
   server => '127.0.0.1',
   port   => '3306',
);
$protocol->{_no_save_error} = 1;
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump040.txt",
   desc     => 'Error (issue 670)',
   result =>
   [
      {
         Error_msg          => "You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near '' at line 1",
         Error_no           => '1064',
         No_good_index_used => 'No',
         No_index_used      => 'No',
         Query_time         => '0.000316',
         Rows_affected      => 0,
         Thread_id          => '4294967296',
         Warning_count      => 0,
         arg                => 'select',
         bytes              => 6,
         cmd                => 'Query',
         db                 => undef,
         host               => '127.0.0.1',
         ip                 => '127.0.0.1',
         port               => '39640',
         pos_in_log         => 0,
         ts                 => '091101 14:54:44.293453',
         user               => undef,
      },
      {
         Error_msg          => 'Unknown system variable \'nono\'',
         Error_no           => '1193',
         No_good_index_used => 'No',
         No_index_used      => 'No',
         Query_time         => '0.000329',
         Rows_affected      => 0,
         Thread_id          => '4294967296',
         Warning_count      => 0,
         arg                => 'set global nono = 2',
         bytes              => 19,
         cmd                => 'Query',
         db                 => undef,
         host               => '127.0.0.1',
         ip                 => '127.0.0.1',
         port               => '39640',
         pos_in_log         => 1250,
         ts                 => '091101 14:54:52.813941',
         user               => undef,
      },
   ],
);

# #############################################################################
# Bug 1103045: pt-query-digest fails to parse non-SQL errors
# https://bugs.launchpad.net/percona-toolkit/+bug/1103045
# #############################################################################

$protocol = new MySQLProtocolParser(
   server => '127.0.0.1',
   port   => '12345',
);

test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump043.txt",
   desc     => 'Bad connection',
   result =>
   [
      {
         Error_msg          => 'Got packets out of order',
         Error_no           => 1156,
         No_good_index_used => 'No',
         No_index_used      => 'No',
         Query_time         => '3.536306',
         Rows_affected      => 0,
         Thread_id          => 27,
         Warning_count      => 0,
         arg                => 'administrator command: Connect',
         bytes              => 30,
         cmd                => 'Admin',
         db                 => undef,
         host               => '127.0.0.1',
         ip                 => '127.0.0.1',
         port               => '62160',
         pos_in_log         => undef,
         ts                 => '130124 13:03:28.672987',
         user               => undef,
      }
   ],
);

test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump042.txt",
   desc     => 'Client went away during handshake',
   result   => [
      {
         No_good_index_used => 'No',
         No_index_used     => 'No',
         Query_time        => '9.998411',
         Rows_affected     => 0,
         Thread_id         => 24,
         Warning_count     => 0,
         arg               => 'administrator command: Connect',
         bytes             => 30,
         cmd               => 'Admin',
         db                => undef,
         host              => '127.0.0.1',
         ip                => '127.0.0.1',
         port              => '62133',
         pos_in_log        => undef,
         ts                => '130124 12:55:48.274417',
         user              => undef,
         Error_msg         => 'Client closed connection during handshake',
      }
   ],
);

$protocol = new MySQLProtocolParser(
   server => '100.0.0.1',
);

test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => "$sample/tcpdump044.txt",
   desc     => 'Client aborted connection (bug 1103045)',
   result   => [
      {
         No_good_index_used   => 'No',
         No_index_used        => 'No',
         Query_time           => '3.819507',
         Rows_affected        => 0,
         Thread_id            => 13,
         Warning_count        => 0,
         arg                  => 'administrator command: Connect',
         bytes                => 30,
         cmd                  => 'Admin',
         db                   => undef,
         host                 => '100.0.0.2',
         ip                   => '100.0.0.2',
         port                 => '44432',
         pos_in_log           => undef,
         ts                   => '130122 09:55:57.793375',
         user                 => undef,
         Error_msg            => 'Client closed connection during handshake',
      },
   ],
);

# #############################################################################
# Save errors by default
# #############################################################################
$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'3306');

my $out = output(sub {
      open my $fh, "<", "$sample/tcpdump032.txt" or die "Cannot open tcpdump032.txt: $OS_ERROR";
      my %parser_args = (
         next_event => sub { return <$fh>; },
         tell       => sub { return tell($fh);  },
      );
      while ( my $p = $tcpdump->parse_event(%parser_args) ) {
         $protocol->parse_event(%parser_args, event => $p);
      }
      close $fh;
}, stderr => 1);

like(
   $out,
   qr/had errors, will save them in /,
   "Saves errors by default"
);
      
close $protocol->{errors_fh}; # flush the handle

like(
   slurp_file($protocol->{errors_file}),
   qr/got server response before full buffer/,
   "The right error is saved"
);

$out = output(sub {
      open my $fh, "<", "$sample/tcpdump032.txt" or die "Cannot open tcpdump032.txt: $OS_ERROR";
      my %parser_args = (
         next_event => sub { return <$fh>; },
         tell       => sub { return tell($fh);  },
      );
      while ( my $p = $tcpdump->parse_event(%parser_args) ) {
         $protocol->parse_event(%parser_args, event => $p);
      }
      close $fh;
}, stderr => 1);

is(
   $out,
   '',
   "No warnings the second time around"
);
      
{
$protocol = new MySQLProtocolParser(server=>'127.0.0.1',port=>'3306');
# ..but allow setting the filename through an ENV var:
local $ENV{PERCONA_TOOLKIT_TCP_ERRORS_FILE} = '/dev/null';

$out = output(sub {
      open my $fh, "<", "$sample/tcpdump032.txt" or die "Cannot open tcpdump032.txt: $OS_ERROR";
      my %parser_args = (
         next_event => sub { return <$fh>; },
         tell       => sub { return tell($fh);  },
      );
      while ( my $p = $tcpdump->parse_event(%parser_args) ) {
         $protocol->parse_event(%parser_args, event => $p);
      }
      close $fh;
}, stderr => 1);

like(
   $out,
   qr/had errors, will save them in /,
   "Still tries saving the errors with PERCONA_TOOLKIT_TCP_ERRORS_FILE"
);

is(
   $protocol->{errors_file},
   '/dev/null',
   "...but uses the provided file"
);
}
# #############################################################################
# Done.
# #############################################################################

# Get rid of error files
`rm /tmp/MySQLProtocolParser.t-errors.*`;
done_testing;
