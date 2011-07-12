#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 28;

use MemcachedProtocolParser;
use TcpdumpParser;
use PerconaTest;

my $tcpdump  = new TcpdumpParser();
my $protocol; # Create a new MemcachedProtocolParser for each test.

# A session with a simple set().
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump001.txt',
   result   => [
      {  ts            => '2009-07-04 21:33:39.229179',
         host          => '127.0.0.1',
         cmd           => 'set',
         key           => 'my_key',
         val           => 'Some value',
         flags         => '0',
         exptime       => '0',
         bytes         => '10',
         res           => 'STORED',
         Query_time    => sprintf('%.6f', .229299 - .229179),
         pos_in_log    => 0,
      },
   ],
);

# A session with a simple get().
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump002.txt',
   result   => [
      {  Query_time => '0.000067',
         cmd        => 'get',
         key        => 'my_key',
         val        => 'Some value',
         bytes      => 10,
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         pos_in_log => '0',
         res        => 'VALUE',
         ts         => '2009-07-04 22:12:06.174390'
      },
   ],
);

# A session with a simple incr() and decr().
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump003.txt',
   result   => [
      {  Query_time => '0.000073',
         cmd        => 'incr',
         key        => 'key',
         val        => '8',
         bytes      => 0,
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         pos_in_log => '0',
         res        => '',
         ts         => '2009-07-04 22:12:06.175734',
      },
      {  Query_time => '0.000068',
         cmd        => 'decr',
         bytes      => 0,
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         key        => 'key',
         pos_in_log => 522,
         res        => '',
         ts         => '2009-07-04 22:12:06.176181',
         val => '7',
      },
   ],
);

# A session with a simple incr() and decr(), but the value doesn't exist.
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump004.txt',
   result   => [
      {  Query_time => '0.000131',
         bytes      => 0,
         cmd        => 'incr',
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         key        => 'key',
         pos_in_log => 764,
         res        => 'NOT_FOUND',
         ts         => '2009-07-06 10:37:21.668469',
         val        => '',
      },
      {
         Query_time => '0.000055',
         bytes      => 0,
         cmd        => 'decr',
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         key        => 'key',
         pos_in_log => 1788,
         res        => 'NOT_FOUND',
         ts         => '2009-07-06 10:37:21.668851',
         val        => '',
      },
   ],
);

# A session with a huge set() that will not fit into a single TCP packet.
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump005.txt',
   result   => [
      {  Query_time => '0.003928',
         bytes      => 17946,
         cmd        => 'set',
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         key        => 'my_key',
         pos_in_log => 764,
         res        => 'STORED',
         ts         => '2009-07-06 22:07:14.406827',
         val        => ('lorem ipsum dolor sit amet' x 690) . ' fini!',
      },
   ],
);

# A session with a huge get() that will not fit into a single TCP packet.
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump006.txt',
   result   => [
      {
         Query_time => '0.000196',
         bytes      => 17946,
         cmd        => 'get',
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         key        => 'my_key',
         pos_in_log => 0,
         res        => 'VALUE',
         ts         => '2009-07-06 22:07:14.411331',
         val        => ('lorem ipsum dolor sit amet' x 690) . ' fini!',
      },
   ],
);

# A session with a get() that doesn't exist.
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump007.txt',
   result   => [
      {
         Query_time => '0.000016',
         bytes      => 0,
         cmd        => 'get',
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         key        => 'comment_v3_482685',
         pos_in_log => 0,
         res        => 'NOT_FOUND',
         ts         => '2009-06-11 21:54:49.059144',
         val        => '',
      },
   ],
);

# A session with a huge get() that will not fit into a single TCP packet, but
# the connection seems to be broken in the middle of the receive and then the
# new client picks up and asks for something different.
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump008.txt',
   result   => [
      {
         Query_time => '0.000003',
         bytes      => 17946,
         cmd        => 'get',
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         key        => 'my_key',
         pos_in_log => 0,
         res        => 'INTERRUPTED',
         ts         => '2009-07-06 22:07:14.411331',
         val        => '',
      },
      {  Query_time => '0.000001',
         cmd        => 'get',
         key        => 'my_key',
         val        => 'Some value',
         bytes      => 10,
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         pos_in_log => 5382,
         res        => 'VALUE',
         ts         => '2009-07-06 22:07:14.411334',
      },
   ],
);

# A session with a delete() that doesn't exist. TODO: delete takes a queue_time.
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump009.txt',
   result   => [
      {
         Query_time => '0.000022',
         bytes      => 0,
         cmd        => 'delete',
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         key        => 'comment_1873527',
         pos_in_log => 0,
         res        => 'NOT_FOUND',
         ts         => '2009-06-11 21:54:52.244534',
         val        => '',
      },
   ],
);

# A session with a delete() that does exist.
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump010.txt',
   result   => [
      {
         Query_time => '0.000120',
         bytes      => 0,
         cmd        => 'delete',
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         key        => 'my_key',
         pos_in_log => 0,
         res        => 'DELETED',
         ts         => '2009-07-09 22:00:29.066476',
         val        => '',
      },
   ],
);

# #############################################################################
# Issue 537: MySQLProtocolParser and MemcachedProtocolParser do not handle
# multiple servers.
# #############################################################################
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump011.txt',
   result   => [
      {  Query_time => '0.000067',
         cmd        => 'get',
         key        => 'my_key',
         val        => 'Some value',
         bytes      => 10,
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.8',
         pos_in_log => '0',
         res        => 'VALUE',
         ts         => '2009-07-04 22:12:06.174390'
      },
      {  ts            => '2009-07-04 21:33:39.229179',
         host          => '127.0.0.9',
         cmd           => 'set',
         key           => 'my_key',
         val           => 'Some value',
         flags         => '0',
         exptime       => '0',
         bytes         => '10',
         res           => 'STORED',
         Query_time    => sprintf('%.6f', .229299 - .229179),
         pos_in_log    => 638,
      },
   ],
);

# #############################################################################
# Issue 544: memcached parse error
# #############################################################################

# Multiple delete in one packet.
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump014.txt',
   result   => [
      {  ts          => '2009-10-06 10:31:56.323538',
         Query_time  => '0.000024',
         bytes       => 0,
         cmd         => 'delete',
         exptime     => 0,
         flags       => 0,
         host        => '10.0.0.5',
         key         => 'ABBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBC',
         pos_in_log  => 0,
         res         => 'NOT_FOUND',
         val         => ''
      },
   ],
);

# Multiple mixed commands: get delete delete
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump015.txt',
   result   => [
      {  ts          => '2009-10-06 10:31:56.330709',
         Query_time  => '0.000013',
         bytes       => 0,
         cmd         => 'get',
         exptime     => 0,
         flags       => 0,
         host        => '10.0.0.5',
         key         => 'ABBBBBBBBBBBBBBBBBBBBBC',
         pos_in_log  => 0,
         res         => 'NOT_FOUND',
         
         val => ''
      },
   ],
);


# #############################################################################
# Issue 818: mk-query-digest: error parsing memcached dump - use of
# uninitialized value in addition
# #############################################################################

# A replace command.
$protocol = new MemcachedProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/memcached/memc_tcpdump016.txt',
   result   => [
      {  ts         => '2010-01-20 10:27:18.510727',
         Query_time => '0.000030',
         bytes      => 56,
         cmd        => 'replace',
         exptime    => '43200',
         flags      => '1',
         host       => '192.168.0.3',
         key        => 'BD_Uk_cms__20100120_095702tab_containerId_410',
         pos_in_log => 0,
         res        => 'STORED',
         val        => 'a:3:{i:0;s:6:"a:0:{}";i:1;i:1263983238;i:2;s:5:"43200";}'
      },
      {  ts         => '2010-01-20 10:27:18.510876',
         Query_time => '0.000066',
         bytes      => '56',
         cmd        => 'get',
         exptime    => 0,
         flags      => '1',
         host       => '192.168.0.3',
         key        => 'BD_Uk_cms__20100120_095702tab_containerId_410',
         pos_in_log => 893,
         res        => 'VALUE',
         val        => 'a:3:{i:0;s:6:"a:0:{}";i:1;i:1263983238;i:2;s:5:"43200";}'
      }
   ],
);

# #############################################################################
# Done.
# #############################################################################
exit;
