#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 15;

use MemcachedEvent;
use PerconaTest;

my $memce = MemcachedEvent->new();
isa_ok($memce, 'MemcachedEvent');

sub make_events {
   my ( @memc_events ) = @_;
   my @events;
   push @events, map { $memce->parse_event(event=>$_) } @memc_events;
   return \@events;
}

# #############################################################################
# Sanity tests.
# #############################################################################
my $events = make_events(
   {
      key           => 'my_key',
      val           => 'Some value',
      res           => 'STORED',
      Query_time    => 1,
   },
);
is_deeply(
   $events,
   [],
   "Doesn't die when there's no cmd"
);

$events = make_events(
   {
      cmd           => 'unknown_cmd',
      val           => 'Some value',
      res           => 'STORED',
      Query_time    => 1,
   },
);
is_deeply(
   $events,
   [],
   "Doesn't die when there's no key"
);

$events = make_events(
   {
      val           => 'Some value',
      res           => 'STORED',
      Query_time    => 1,
   },
);
is_deeply(
   $events,
   [],
   "Doesn't die when there's no cmd or key"
);

$events = make_events(
   {
      cmd           => 'unknown_cmd',
      key           => 'my_key',
      val           => 'Some value',
      res           => 'STORED',
      Query_time    => 1,
   },
);
is_deeply(
   $events,
   [],
   "Doesn't handle unknown cmd"
);

# #############################################################################
# These events are copied straight from the expected results in
# MemcachedProtocolParser.t.
# #############################################################################

# A session with a simple set().
$events = make_events(
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
);
is_deeply(
   $events,
   [
      {
         arg         => 'set my_key',
         fingerprint => 'set my_key',
         key_print   => 'my_key',
         cmd         => 'set',
         key         => 'my_key',
         res         => 'STORED',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'No',
         Memc_delete => 'No',
         Memc_error => 'No',
         Memc_get => 'No',
         Memc_gets => 'No',
         Memc_incr => 'No',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'Yes',
         Memc_miss   => 'No',
         Memc_error  => 'No',
         Memc_Not_Stored => 'No',
         Memc_Exists     => 'No',
         Query_time => '0.000120',
         bytes => '10',
         exptime => '0',
         fingerprint => 'set my_key',
         flags => '0',
         host => '127.0.0.1',
         pos_in_log => 0,
         ts => '2009-07-04 21:33:39.229179',
         val => 'Some value'
      },
   ],
   'samples/memc_tcpdump001.txt: simple set'
);

# A session with a simple get().
$events = make_events(
   {  Query_time => '0.000067',
      cmd        => 'get',
      key        => 'my_key',
      val        => 'Some value',
      bytes      => 10,
      exptime    => undef,
      flags      => 0,
      host       => '127.0.0.1',
      pos_in_log => '0',
      res        => 'VALUE',
      ts         => '2009-07-04 22:12:06.174390'
   }
);
is_deeply(
   $events,
   [
      {
         arg         => 'get my_key',
         fingerprint => 'get my_key',
         key_print   => 'my_key',
         cmd         => 'get',
         key         => 'my_key',
         res         => 'VALUE',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'No',
         Memc_delete => 'No',
         Memc_error => 'No',
         Memc_get => 'Yes',
         Memc_gets => 'No',
         Memc_incr => 'No',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'No',
         Memc_miss   => 'No',
         Memc_error  => 'No',
         Query_time => '0.000067',
         val        => 'Some value',
         bytes      => 10,
         exptime    => undef,
         flags      => 0,
         host       => '127.0.0.1',
         pos_in_log => '0',
         ts         => '2009-07-04 22:12:06.174390'
      },
   ],
   'samples/memc_tcpdump002.txt: simple get',
);

# A session with a simple incr() and decr().
$events = make_events(
   {  Query_time => '0.000073',
      cmd        => 'incr',
      key        => 'key',
      val        => '8',
      bytes      => undef,
      exptime    => undef,
      flags      => undef,
      host       => '127.0.0.1',
      pos_in_log => '0',
      res        => '',
      ts         => '2009-07-04 22:12:06.175734',
   },
   {  Query_time => '0.000068',
      cmd        => 'decr',
      bytes      => undef,
      exptime    => undef,
      flags      => undef,
      host       => '127.0.0.1',
      key        => 'key',
      pos_in_log => 522,
      res        => '',
      ts         => '2009-07-04 22:12:06.176181',
      val        => '7',
   },
);
is_deeply(
   $events,
   [
      {
         arg         => 'incr key',
         fingerprint => 'incr key',
         key_print   => 'key',
         cmd         => 'incr',
         key         => 'key',
         res         => '',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'No',
         Memc_delete => 'No',
         Memc_error => 'No',
         Memc_get => 'No',
         Memc_gets => 'No',
         Memc_incr => 'Yes',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'No',
         Memc_miss   => 'No',
         Memc_error  => 'No',
         Query_time => '0.000073',
         val        => '8',
         bytes      => undef,
         exptime    => undef,
         flags      => undef,
         host       => '127.0.0.1',
         pos_in_log => '0',
         ts         => '2009-07-04 22:12:06.175734',
      },
      {  
         arg         => 'decr key',
         fingerprint => 'decr key',
         key_print   => 'key',
         cmd         => 'decr',
         key         => 'key',
         res         => '',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'Yes',
         Memc_delete => 'No',
         Memc_error => 'No',
         Memc_get => 'No',
         Memc_gets => 'No',
         Memc_incr => 'No',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'No',
         Memc_miss   => 'No',
         Memc_error  => 'No',
         Query_time => '0.000068',
         bytes      => undef,
         exptime    => undef,
         flags      => undef,
         host       => '127.0.0.1',
         pos_in_log => 522,
         ts         => '2009-07-04 22:12:06.176181',
         val        => '7',
      },
   ],
   'samples/memc_tcpdump003.txt: incr and decr'
);

# A session with a simple incr() and decr(), but the value doesn't exist.
$events = make_events(
   {  Query_time => '0.000131',
      bytes      => undef,
      cmd        => 'incr',
      exptime    => undef,
      flags      => undef,
      host       => '127.0.0.1',
      key        => 'key',
      pos_in_log => 764,
      res        => 'NOT_FOUND',
      ts         => '2009-07-06 10:37:21.668469',
      val        => '',
   },
   {
      Query_time => '0.000055',
      bytes      => undef,
      cmd        => 'decr',
      exptime    => undef,
      flags      => undef,
      host       => '127.0.0.1',
      key        => 'key',
      pos_in_log => 1788,
      res        => 'NOT_FOUND',
      ts         => '2009-07-06 10:37:21.668851',
      val        => '',
   },
);
is_deeply(
   $events,
   [
      {  
         arg         => 'incr key',
         fingerprint => 'incr key',
         key_print   => 'key',
         cmd         => 'incr',
         key         => 'key',
         res         => 'NOT_FOUND',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'No',
         Memc_delete => 'No',
         Memc_error => 'No',
         Memc_get => 'No',
         Memc_gets => 'No',
         Memc_incr => 'Yes',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'No',
         Memc_miss   => 'Yes',
         Memc_error  => 'No',
         Query_time => '0.000131',
         bytes      => undef,
         exptime    => undef,
         flags      => undef,
         host       => '127.0.0.1',
         pos_in_log => 764,
         ts         => '2009-07-06 10:37:21.668469',
         val        => '',
      },
      {
         arg         => 'decr key',
         fingerprint => 'decr key',
         key_print   => 'key',
         cmd         => 'decr',
         key         => 'key',
         res         => 'NOT_FOUND',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'Yes',
         Memc_delete => 'No',
         Memc_error => 'No',
         Memc_get => 'No',
         Memc_gets => 'No',
         Memc_incr => 'No',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'No',
         Memc_miss   => 'Yes',
         Memc_error  => 'No',
         Query_time => '0.000055',
         bytes      => undef,
         exptime    => undef,
         flags      => undef,
         host       => '127.0.0.1',
         pos_in_log => 1788,
         ts         => '2009-07-06 10:37:21.668851',
         val        => '',
      },
   ],
   'samples/memc_tcpdump004.txt: incr and decr nonexistent key'
);

# A session with a huge set() that will not fit into a single TCP packet.
$events = make_events(
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
);
is_deeply(
   $events,
   [
      {  
         arg         => 'set my_key',
         fingerprint => 'set my_key',
         key_print   => 'my_key',
         cmd         => 'set',
         key         => 'my_key',
         res         => 'STORED',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'No',
         Memc_delete => 'No',
         Memc_error => 'No',
         Memc_get => 'No',
         Memc_gets => 'No',
         Memc_incr => 'No',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'Yes',
         Memc_miss  => 'No',
         Memc_error => 'No',
         Memc_Not_Stored => 'No',
         Memc_Exists     => 'No',
         Query_time => '0.003928',
         bytes      => 17946,
         exptime    => 0,
         flags      => 0,
         host       => '127.0.0.1',
         pos_in_log => 764,
         ts         => '2009-07-06 22:07:14.406827',
         val        => ('lorem ipsum dolor sit amet' x 690) . ' fini!',
      },
   ],
   'samples/memc_tcpdump005.txt: huge set'
);

# A session with a huge get() that will not fit into a single TCP packet.
$events = make_events(
   {
      Query_time => '0.000196',
      bytes      => 17946,
      cmd        => 'get',
      exptime    => undef,
      flags      => 0,
      host       => '127.0.0.1',
      key        => 'my_key',
      pos_in_log => 0,
      res        => 'VALUE',
      ts         => '2009-07-06 22:07:14.411331',
      val        => ('lorem ipsum dolor sit amet' x 690) . ' fini!',
   },
);
is_deeply(
   $events,
   [
      {
         arg         => 'get my_key',
         fingerprint => 'get my_key',
         key_print   => 'my_key',
         cmd         => 'get',
         key         => 'my_key',
         res         => 'VALUE',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'No',
         Memc_delete => 'No',
         Memc_error => 'No',
         Memc_get => 'Yes',
         Memc_gets => 'No',
         Memc_incr => 'No',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'No',
         Memc_miss   => 'No',
         Memc_error  => 'No',
         Query_time => '0.000196',
         bytes      => 17946,
         exptime    => undef,
         flags      => 0,
         host       => '127.0.0.1',
         pos_in_log => 0,
         ts         => '2009-07-06 22:07:14.411331',
         val        => ('lorem ipsum dolor sit amet' x 690) . ' fini!',
      },
   ],
   'samples/memc_tcpdump006.txt: huge get'
);

# A session with a get() that doesn't exist.
$events = make_events(
   {
      Query_time => '0.000016',
      bytes      => undef,
      cmd        => 'get',
      exptime    => undef,
      flags      => undef,
      host       => '127.0.0.1',
      key        => 'comment_v3_482685',
      pos_in_log => 0,
      res        => 'NOT_FOUND',
      ts         => '2009-06-11 21:54:49.059144',
      val        => '',
   },
);
is_deeply(
   $events,
   [
      {
         arg         => 'get comment_v3_482685',
         fingerprint => 'get comment_v?_?',
         key_print   => 'comment_v?_?',
         cmd         => 'get',
         key         => 'comment_v3_482685',
         res         => 'NOT_FOUND',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'No',
         Memc_delete => 'No',
         Memc_error => 'No',
         Memc_get => 'Yes',
         Memc_gets => 'No',
         Memc_incr => 'No',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'No',
         Memc_miss   => 'Yes',
         Memc_error  => 'No',
         Query_time => '0.000016',
         bytes      => undef,
         exptime    => undef,
         flags      => undef,
         host       => '127.0.0.1',
         pos_in_log => 0,
         ts         => '2009-06-11 21:54:49.059144',
         val        => '',
      },
   ],
   'samples/memc_tcpdump007.txt: get nonexistent key'
);

# A session with a huge get() that will not fit into a single TCP packet, but
# the connection seems to be broken in the middle of the receive and then the
# new client picks up and asks for something different.
$events = make_events(
   {
      Query_time => '0.000003',
      bytes      => 17946,
      cmd        => 'get',
      exptime    => undef,
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
      exptime    => undef,
      flags      => 0,
      host       => '127.0.0.1',
      pos_in_log => 5382,
      res        => 'VALUE',
      ts         => '2009-07-06 22:07:14.411334',
   },
);
is_deeply(
   $events,
   [
      {
         arg         => 'get my_key',
         fingerprint => 'get my_key',
         key_print   => 'my_key',
         cmd         => 'get',
         key         => 'my_key',
         res         => 'INTERRUPTED',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'No',
         Memc_delete => 'No',
         Memc_error => 'No',
         Memc_get => 'Yes',
         Memc_gets => 'No',
         Memc_incr => 'No',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'No',
         Memc_miss   => 'No',
         Memc_error  => 'Yes',
         Query_time => '0.000003',
         bytes      => 17946,
         exptime    => undef,
         flags      => 0,
         host       => '127.0.0.1',
         pos_in_log => 0,
         ts         => '2009-07-06 22:07:14.411331',
         val        => '',
      },
      {
         arg         => 'get my_key',
         fingerprint => 'get my_key',
         key_print   => 'my_key',
         cmd         => 'get',
         key         => 'my_key',
         res         => 'VALUE',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'No',
         Memc_delete => 'No',
         Memc_error => 'No',
         Memc_get => 'Yes',
         Memc_gets => 'No',
         Memc_incr => 'No',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'No',
         Memc_miss   => 'No',
         Memc_error  => 'No',
         Query_time => '0.000001',
         val        => 'Some value',
         bytes      => 10,
         exptime    => undef,
         flags      => 0,
         host       => '127.0.0.1',
         pos_in_log => 5382,
         ts         => '2009-07-06 22:07:14.411334',
      },
   ],
   'samples/memc_tcpdump008.txt: interrupted huge get'
);

# A session with a delete() that doesn't exist. TODO: delete takes a queue_time.
$events = make_events(
   {
      Query_time => '0.000022',
      bytes      => undef,
      cmd        => 'delete',
      exptime    => undef,
      flags      => undef,
      host       => '127.0.0.1',
      key        => 'comment_1873527',
      pos_in_log => 0,
      res        => 'NOT_FOUND',
      ts         => '2009-06-11 21:54:52.244534',
      val        => '',
   },
);
is_deeply(
   $events,
   [
      {
         arg         => 'delete comment_1873527',
         fingerprint => 'delete comment_?',
         key_print   => 'comment_?',
         cmd         => 'delete',
         key         => 'comment_1873527',
         res         => 'NOT_FOUND',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'No',
         Memc_delete => 'Yes',
         Memc_error => 'No',
         Memc_get => 'No',
         Memc_gets => 'No',
         Memc_incr => 'No',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'No',
         Memc_miss   => 'Yes',
         Memc_error  => 'No',
         Query_time => '0.000022',
         bytes      => undef,
         exptime    => undef,
         flags      => undef,
         host       => '127.0.0.1',
         pos_in_log => 0,
         ts         => '2009-06-11 21:54:52.244534',
         val        => '',
      },
   ],
   'samples/memc_tcpdump009.txt: delete nonexistent key'
);

# A session with a delete() that does exist.
$events = make_events(
   {
      Query_time => '0.000120',
      bytes      => undef,
      cmd        => 'delete',
      exptime    => undef,
      flags      => undef,
      host       => '127.0.0.1',
      key        => 'my_key',
      pos_in_log => 0,
      res        => 'DELETED',
      ts         => '2009-07-09 22:00:29.066476',
      val        => '',
   },
);
is_deeply(
   $events,
   [
      {
         arg         => 'delete my_key',
         fingerprint => 'delete my_key',
         key_print   => 'my_key',
         cmd         => 'delete',
         key         => 'my_key',
         res         => 'DELETED',
         Memc_add => 'No',
         Memc_append => 'No',
         Memc_cas => 'No',
         Memc_decr => 'No',
         Memc_delete => 'Yes',
         Memc_error => 'No',
         Memc_get => 'No',
         Memc_gets => 'No',
         Memc_incr => 'No',
         Memc_miss => 'No',
         Memc_prepend => 'No',
         Memc_replace => 'No',
         Memc_set => 'No',
         Memc_miss   => 'No',
         Memc_error  => 'No',
         Query_time => '0.000120',
         bytes      => undef,
         exptime    => undef,
         flags      => undef,
         host       => '127.0.0.1',
         pos_in_log => 0,
         ts         => '2009-07-09 22:00:29.066476',
         val        => '',
      },
   ],
   'samples/memc_tcpdump010.txt: simple delete'
);

# #############################################################################
# Done.
# #############################################################################
exit;
