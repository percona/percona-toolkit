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

use Processlist;
use PerconaTest;
use TextResultSetParser;
use Transformers;
use MasterSlave;
use PerconaTest;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $ms  = new MasterSlave(OptionParser=>1,DSNParser=>1,Quoter=>1);
my $rsp = new TextResultSetParser();
my $pl;
my $procs;
my @events;

sub parse_n_times {
   my ( $n, %args ) = @_;
   @events = ();
   for ( 1..$n ) {
      my $event = $pl->parse_event(%args);
      push @events, $event if $event;
   }
}

# ###########################################################################
# A cxn that's connecting should be seen but ignored until it begins
# to execute a query.
# ###########################################################################
$pl = new Processlist(MasterSlave=>$ms);

$procs = [
   [ [1, 'unauthenticated user', 'localhost', undef, 'Connect', undef,
    'Reading from net', undef] ],
    [],[],
],

parse_n_times(
   3,
   code  => sub {
      return shift @$procs;
   },
   time  => Transformers::unix_timestamp('2001-01-01 00:05:00'),
);

is(
   scalar @events,
   0,
   "No events for new cxn still connecting"
);

is_deeply(
   $pl->_get_active_cxn(),
   {},
   "Cxn not saved because it's not executing a query"
);

# ###########################################################################
# A sleeping cxn that goes aways should be safely ignored.
# ###########################################################################
$pl = Processlist->new(MasterSlave=>$ms);

parse_n_times(
   1,
   code => sub {
      return [ [1, 'root', 'localhost', undef, 'Sleep', 7, '', undef], ];
   },
   time => Transformers::unix_timestamp('2001-01-01 00:05:00'),
);

# And now the connection goes away...
parse_n_times(
   1,
   code => sub { return []; },
   time => Transformers::unix_timestamp('2001-01-01 00:05:01'),
);

is(
   scalar @events,
   0,
   "No events for sleep cxn that went away"
);

is_deeply(
   $pl->_get_active_cxn(),
   {},
   "Sleeping cxn not saved"
);

# ###########################################################################
# A more life-like test with multiple queries that come, execute and go away.
# ###########################################################################
$pl = Processlist->new(MasterSlave=>$ms);

# The initial processlist shows a query in progress.
parse_n_times(
   1,
   code  => sub {
      return [
         [1, 'root', 'localhost', 'test', 'Query', 2, 'executing', 'query1_1'],
      ],
   },
   time  => Transformers::unix_timestamp('2001-01-01 00:05:00'),
   etime => .05,
);

is(
   scalar @events,
   0,
   'No events fired'
);

# The should now be active cxn with a query that started 2 seconds ago.
is_deeply(
   $pl->_get_active_cxn(),
   {
      1 => [
         1, 'root', 'localhost', 'test', 'Query', 2, 'executing', 'query1_1',
         Transformers::unix_timestamp('2001-01-01 00:04:58'),   # START
         0.05,                                                  # ETIME
         Transformers::unix_timestamp('2001-01-01 00:05:00'),   # FSEEN
         { executing => 0 },
      ],
   },
   "Cxn 1 is active"
);

# The next processlist shows a new cxn/query in progress and the first
# one (above) has ended.
$procs = [
   [ [2, 'root', 'localhost', 'test', 'Query', 1, 'executing', 'query2_1'] ],
];

parse_n_times(
   1, 
   code  => sub {
      return shift @$procs,
   },
   time  => Transformers::unix_timestamp('2001-01-01 00:05:01'),
   etime => .03,
);

# Event should have been made for the first query.
is_deeply(
   \@events,
   [  {  db         => 'test',
         user       => 'root',
         host       => 'localhost',
         arg        => 'query1_1',
         bytes      => 8,
         ts         => '2001-01-01T00:05:00',
         Query_time => 2,
         Lock_time  => 0,
         id         => 1,
      },
   ],
   'query1_1 fired',
) or print Dumper(\@events);

# Only the 2nd cxn/query should be active now.
is_deeply(
   $pl->_get_active_cxn(),
   {
      2 => [
         2, 'root', 'localhost', 'test', 'Query', 1, 'executing', 'query2_1',
         Transformers::unix_timestamp('2001-01-01 00:05:00'),   # START
         .03,                                                   # ETIME
         Transformers::unix_timestamp('2001-01-01 00:05:01'),   # FSEEN
         { executing => 0 },
      ],
   },
   "Only cxn 2 is active"
);

# The query on cxn 2 is finished, but the connection is still open.
parse_n_times(
   1,
   code  => sub {
      return [
         [ 2, 'root', 'localhost', 'test', 'Sleep', 0, '', undef],
      ],
   },
   time  => Transformers::unix_timestamp('2001-01-01 00:05:02'),
);

# And so as a result, query2_1 has fired...
is_deeply(
   \@events,
   [  {  db         => 'test',
         user       => 'root',
         host       => 'localhost',
         arg        => 'query2_1',
         bytes      => 8,
         ts         => '2001-01-01T00:05:01',
         Query_time => 1,
         Lock_time  => 0,
         id         => 2,
      },
   ],
   'query2_1 fired',
);

# ...and there's no more active cxn.
is_deeply(
   $pl->_get_active_cxn(),
   {},
   "No active cxn"
);

# In this sample, cxn 2 is running a query, with a start time at the current
# time of 3 secs later
parse_n_times(
   1,
   code  => sub {
      return [
         [ 2, 'root', 'localhost', 'test', 'Query', 0, 'executing', 'query2_2'],
      ],
   },
   time  => Transformers::unix_timestamp('2001-01-01 00:05:03'),
   etime => 3.14159,
);

is_deeply(
   $pl->_get_active_cxn(),
   {
      2 => [
         2, 'root', 'localhost', 'test', 'Query', 0, 'executing', 'query2_2',
         Transformers::unix_timestamp('2001-01-01 00:05:03'),   # START
         3.14159,                                               # ETIME
         Transformers::unix_timestamp('2001-01-01 00:05:03'),   # FSEEN
         { executing => 0 },
      ],
   },
   'query2_2 just started',
);

# And there is no event on cxn 2.
is(
   scalar @events,
   0,
   'query2_2 has not fired yet',
);

# In this sample, the "same" query is running one second later and this time it
# seems to have a start time of 5 secs later, which is not enough to be a new
# query.
parse_n_times(
   1,
   code  => sub {
      return [
         [ 2, 'root', 'localhost', 'test', 'Query', 0, 'executing', 'query2_2'],
      ],
   },
   time  => Transformers::unix_timestamp('2001-01-01 00:05:05'),
   etime => 2.718,
);

is(
   scalar @events,
   0,
      'query2_2 has not fired yet',
);

# And so as a result, query2_2 has NOT fired, but the query is still active.
is_deeply(
   $pl->_get_active_cxn(),
   {
      2 => [
         2, 'root', 'localhost', 'test', 'Query', 0, 'executing', 'query2_2',
         Transformers::unix_timestamp('2001-01-01 00:05:03'),
         3.14159,
         Transformers::unix_timestamp('2001-01-01 00:05:03'),
         { executing => 2 },
      ],
   },
   'Cxn 2 still active with query starting at 05:03',
);

# But wait!  There's another!  And this time we catch it!
parse_n_times(
   1,
   code  => sub {
      return [
         [ 2, 'root', 'localhost', 'test', 'Query', 0, 'executing', 'query2_2'],
      ],
   },
   time  => Transformers::unix_timestamp('2001-01-01 00:05:08.500'),
   etime => 0.123,
);

is_deeply(
   \@events,
   [  {  db         => 'test',
         user       => 'root',
         host       => 'localhost',
         arg        => 'query2_2',
         bytes      => 8,
         ts         => '2001-01-01T00:05:03',
         Query_time => 5.5,
         Lock_time  => 0,
         id         => 2,
      },
   ],
   'Original query2_2 fired',
);

# And so as a result, query2_2 has fired and the prev array contains the "new"
# query2_2.
is_deeply(
   $pl->_get_active_cxn(),
   {
      2 => [
         2, 'root', 'localhost', 'test', 'Query', 0, 'executing', 'query2_2',
         Transformers::unix_timestamp('2001-01-01 00:05:08'),
         0.123,
         Transformers::unix_timestamp('2001-01-01 00:05:08.500'),
         { executing => 0 },
      ],
   },
   "New query2_2 is active, starting at 05:08"
);


# ###########################################################################
# pt-query-digest --processlist: Duplicate entries for replication thread
# https://bugs.launchpad.net/percona-toolkit/+bug/1156901
# ###########################################################################

# This is basically the same thing as above, but we're pretending to
# be a repl thread, so it should behave differently.

$pl = Processlist->new(MasterSlave=>$ms);

parse_n_times(
   1,
   code  => sub {
      return [
         [ 2, 'system user', 'localhost', 'test', 'Query', 0, 'executing', 'query2_2'],
      ],
   },
   time  => Transformers::unix_timestamp('2001-01-01 00:05:03'),
   etime => 3.14159,
);

is_deeply(
   $pl->_get_active_cxn(),
   {
      2 => [
         2, 'system user', 'localhost', 'test', 'Query', 0, 'executing', 'query2_2',
         Transformers::unix_timestamp('2001-01-01 00:05:03'),   # START
         3.14159,                                               # ETIME
         Transformers::unix_timestamp('2001-01-01 00:05:03'),   # FSEEN
         { executing => 0 },
      ],
   },
   'query2_2 just started',
);

# And there is no event on cxn 2.
is(
   scalar @events,
   0,
   'query2_2 has not fired yet',
);

parse_n_times(
   1,
   code  => sub {
      return [
         [ 2, 'system user', 'localhost', 'test', 'Query', 0, 'executing', 'query2_2'],
      ],
   },
   time  => Transformers::unix_timestamp('2001-01-01 00:05:05'),
   etime => 2.718,
);

is(
   scalar @events,
   0,
      'query2_2 has not fired yet, same as with normal queries',
);

is_deeply(
   $pl->_get_active_cxn(),
   {
      2 => [
         2, 'system user', 'localhost', 'test', 'Query', 0, 'executing', 'query2_2',
         Transformers::unix_timestamp('2001-01-01 00:05:03'),
         3.14159,
         Transformers::unix_timestamp('2001-01-01 00:05:03'),
         { executing => 2 },
      ],
   },
   'Cxn 2 still active with query starting at 05:03',
);

# Same as above but five seconds and a half later
parse_n_times(
   1,
   code  => sub {
      return [
         [ 2, 'system user', 'localhost', 'test', 'Query', 0, 'executing', 'query2_2'],
      ],
   },
   time  => Transformers::unix_timestamp('2001-01-01 00:05:08.500'),
   etime => 0.123,
);

is_deeply(
   \@events,
   [],
   'Original query2_2 not fired because we are a repl thrad',
);

is_deeply(
   $pl->_get_active_cxn(),
   {
      2 => [
         2, 'system user', 'localhost', 'test', 'Query', 0, 'executing', 'query2_2',
         Transformers::unix_timestamp('2001-01-01 00:05:03'),   # START
         3.14159,                                               # ETIME
         Transformers::unix_timestamp('2001-01-01 00:05:03'),   # FSEEN
         { executing => 5.5 },
      ],
   },
   "Old query2_2 is active because we're a repl thread, but executing has updated"
);

# ###########################################################################
# Issue 867: Make mk-query-digest detect Lock_time from processlist
# ###########################################################################
$ms  = new MasterSlave(OptionParser=>1,DSNParser=>1,Quoter=>1);
$pl = Processlist->new(MasterSlave=>$ms);

# For 2/10ths of a second, the query is Locked.  First time we see this
# cxn and query, we don't/can't know how much of it's execution Time was
# Locked or something else, so the first 1/10th second of Locked time is
# ignored and the 2nd tenth is counted.  Then...
parse_n_times(
   1,
   code  => sub {
      return [
         [1, 'root', 'localhost', 'test', 'Query', 0, 'Locked', 'query1_1'],
      ],
   },
   time  => Transformers::unix_timestamp('2011-01-01 00:00:00.2'),
   etime => .1,
);
parse_n_times(
   1,
   code  => sub {
      return [
         [1, 'root', 'localhost', 'test', 'Query', 0, 'Locked', 'query1_1'],
      ],
   },
   time  => Transformers::unix_timestamp('2011-01-01 00:00:00.4'),
   etime => .1,
);

# ...when the query changes states, we guesstimate that half the poll time
# between state changes was in the previous state, and the other half in
# the new/current state.  So Locked picks up 0.05 (1/2 of 1/10), bringing
# its total to 0.15.
parse_n_times(
   1,
   code  => sub {
      return [
         [1, 'root', 'localhost', 'test', 'Query', 0, 'executing', 'query1_1'],
      ],
   },
   time  => Transformers::unix_timestamp('2011-01-01 00:00:00.6'),
   etime => .1,
);

parse_n_times(
   1,
   code  => sub {
      return [
         [1, 'root', 'localhost', 'test', 'Sleep', 0, '', undef],
      ],
   },
   time  => Transformers::unix_timestamp('2011-01-01 00:00:00.8'),
   etime => .1,
);

$events[0]->{Lock_time} = sprintf '%.1f', $events[0]->{Lock_time};
is(
   $events[0]->{Lock_time},
   0.3,
   "Detects Lock_time from Locked state"
);

# Query_time should be 0.6 because it it was first seen at :00.2 and
# then ends at :00.8.  So .8 - .2 = .6.
ok(
      $events[0]->{Query_time} >= 0.58
   && $events[0]->{Query_time} <= 0.69,
   "Query_time is accurate (0.58 <= t <= 0.69)"
);

# ###########################################################################
# Issue 1252: mk-query-digest --processlist does not work well
# ###########################################################################
$pl = Processlist->new(MasterSlave=>$ms);

# @ :10.0
# First call we have 3 queries, none of which are finished.  This poll
# actually started at :10.0 but took .5s to complete so time=:10.5.
parse_n_times(
   1,
   code  => sub {
      return [
         [1, 'root', 'localhost', 'test', 'Query', 1, 'Locked',    'query1'],
         [2, 'root', 'localhost', 'test', 'Query', 2, 'executing', 'query2'],
         [3, 'root', 'localhost', 'test', 'Query', 3, 'executing', 'query3'],
      ],
   },
   time  => Transformers::unix_timestamp('2011-01-01 00:00:10.5'),
   etime => 0.5,
);
is_deeply(
   \@events,
   [],
   "No events yet (issue 1252)"
) or print Dumper(\@events);

is_deeply(
   $pl->_get_active_cxn(),
   {
      1 => [
         1, 'root', 'localhost', 'test', 'Query', 1, 'Locked',    'query1',
         Transformers::unix_timestamp('2011-01-01 00:00:09'),   # START
         0.5,                                                   # ETIME
         Transformers::unix_timestamp('2011-01-01 00:00:10.5'), # FSEEN
         { Locked => 0 },
      ],
      2 => [
         2, 'root', 'localhost', 'test', 'Query', 2, 'executing', 'query2',
         Transformers::unix_timestamp('2011-01-01 00:00:08'),   # START
         0.5,                                                   # ETIME
         Transformers::unix_timestamp('2011-01-01 00:00:10.5'), # FSEEN
         { executing => 0 },
      ],
      3 => [
         3, 'root', 'localhost', 'test', 'Query', 3, 'executing', 'query3',
         Transformers::unix_timestamp('2011-01-01 00:00:07'),   # START
         0.5,                                                   # ETIME
         Transformers::unix_timestamp('2011-01-01 00:00:10.5'), # FSEEN
         { executing => 0 },
      ],
   },
   "All three cxn are active (issue 1252)"
);

# @ :11.0
# Second call queries 3 & 2 have finished, so we should get an event for
# one of them and the other will be cached.  Also note: query 1 has changed
# from Locked to executing. -- This poll actually started at :11.0 but took
# 0.1s to complete so time=:11.1.
parse_n_times(
   1,
   code  => sub {
      return [
         [1, 'root', 'localhost', 'test', 'Query', 1, 'executing', 'query1'],
      ],
   },
   time  => Transformers::unix_timestamp('2011-01-01 00:00:11.1'),
   etime => 0.1,
);

# Processlist uses hashes so the returns may be unpredictable due to
# keys/values %$hash being unpredictable.  So we save the returns, then
# sort them later by cxn ID.
my @event_q;
push @event_q, @events;

is(
   scalar @events,
   1,
   "2nd call, an event returned (issue 1252)"
);

# @ :11.0
# Third call finishes query 1 but should returned cached event first
# since it finished at 2nd call. -- No poll happens until all cached
# events are returned.
parse_n_times(
   1,
   code  => sub { return []; },
   time  => Transformers::unix_timestamp('2011-01-01 00:00:11.1'),
   etime => 0.5,
);

is(
   scalar @events,
   1,
   "3rd call, another event returned (issue 1252)"
) or print Dumper(\@events);

push @event_q, @events;
@event_q = sort { $a->{id} <=> $b->{id} } @event_q;
is_deeply(
   \@event_q,
   [ {
      Lock_time   => 0,
      Query_time  => 2,
      arg         => 'query2',
      bytes       => 6,
      db          => 'test',
      host        => 'localhost',
      id          => 2,
      ts          => '2011-01-01T00:00:10',
      user        => 'root'
   },
   {
      Lock_time   => 0,
      Query_time  => 3,
      arg         => 'query3',
      bytes       => 6,
      db          => 'test',
      host        => 'localhost',
      id          => 3,
      ts          => '2011-01-01T00:00:10',
      user        => 'root'
   } ],
   "Cxn 2 and 3 finished (issue 1252)",
) or print Dumper(\@event_q);

# @ :11.5
# Fourth call returns query1 that finished last call. -- This poll
# actually happens at :11.5 and took 0.2s to complete so time=:11.7.
parse_n_times(
   1,
   code  => sub { return []; },
   time  => Transformers::unix_timestamp('2011-01-01 00:00:11.7'),
   etime => 0.2,
);

# This query was first seen at :10.5 and then was done and gone by :11.7.
# Thus we observed it for 1.2s.  Actually, the query was last seen at :11.1,
# so between then and :11.7 is .6s, i.e. one poll interval.  So the query
# really ended sometime during the poll interval :11.1-:11.7.
$events[0]->{Query_time} = sprintf '%.6f', $events[0]->{Query_time};
$events[0]->{Lock_time}  = sprintf '%.2f', $events[0]->{Lock_time};
is_deeply(
   \@events,
   [ {
      Lock_time   => '0.30',
      Query_time  => '1.200000',
      arg         => 'query1',
      bytes       => 6,
      db          => 'test',
      host        => 'localhost',
      id          => 1,
      ts          => '2011-01-01T00:00:10',
      user        => 'root'
   } ],
   "4th call, last finished event (issue 1252)"
) or print Dumper(\@events);

# @ :12.0
# Fifth call returns nothing because there's no events.
parse_n_times(
   1,
   code  => sub { return []; },
   time  => Transformers::unix_timestamp('2011-01-01 00:00:12.0'),
   etime => 0.1,
);

is(
   scalar @events,
   0,
   "No events (issue 1252)"
) or print Dumper(\@events);

# ###########################################################################
# Tests for "find" functionality.
# ###########################################################################

my %find_spec = (
   busy_time    => 60,
   idle_time    => 0,
   ignore => {
      Id       => 5,
      User     => qr/^system.user$/,
      State    => qr/Locked/,
      Command  => qr/Binlog Dump/,
   },
   match => {
      Command  => qr/Query/,
      Info     => qr/^(?i:select)/,
   },
);

my $matching_query =
      {  'Time'    => '91',
         'Command' => 'Query',
         'db'      => undef,
         'Id'      => '43',
         'Info'    => 'select * from foo',
         'User'    => 'msandbox',
         'State'   => 'executing',
         'Host'    => 'localhost'
      };

my @queries = $pl->find(
   [  {  'Time'    => '488',
         'Command' => 'Connect',
         'db'      => undef,
         'Id'      => '4',
         'Info'    => undef,
         'User'    => 'system user',
         'State'   => 'Waiting for master to send event',
         'Host'    => ''
      },
      {  'Time'    => '488',
         'Command' => 'Connect',
         'db'      => undef,
         'Id'      => '5',
         'Info'    => undef,
         'User'    => 'system user',
         'State' =>
            'Has read all relay log; waiting for the slave I/O thread to update it',
         'Host' => ''
      },
      {  'Time'    => '416',
         'Command' => 'Sleep',
         'db'      => undef,
         'Id'      => '7',
         'Info'    => undef,
         'User'    => 'msandbox',
         'State'   => '',
         'Host'    => 'localhost'
      },
      {  'Time'    => '0',
         'Command' => 'Query',
         'db'      => undef,
         'Id'      => '8',
         'Info'    => 'show full processlist',
         'User'    => 'msandbox',
         'State'   => undef,
         'Host'    => 'localhost:41655'
      },
      {  'Time'    => '467',
         'Command' => 'Binlog Dump',
         'db'      => undef,
         'Id'      => '2',
         'Info'    => undef,
         'User'    => 'msandbox',
         'State' =>
            'Has sent all binlog to slave; waiting for binlog to be updated',
         'Host' => 'localhost:56246'
      },
      {  'Time'    => '91',
         'Command' => 'Sleep',
         'db'      => undef,
         'Id'      => '40',
         'Info'    => undef,
         'User'    => 'msandbox',
         'State'   => '',
         'Host'    => 'localhost'
      },
      {  'Time'    => '91',
         'Command' => 'Query',
         'db'      => undef,
         'Id'      => '41',
         'Info'    => 'optimize table foo',
         'User'    => 'msandbox',
         'State'   => 'Query',
         'Host'    => 'localhost'
      },
      {  'Time'    => '91',
         'Command' => 'Query',
         'db'      => undef,
         'Id'      => '42',
         'Info'    => 'select * from foo',
         'User'    => 'msandbox',
         'State'   => 'Locked',
         'Host'    => 'localhost'
      },
      $matching_query,
   ],
   %find_spec,
);

my $expected = [ $matching_query ];

is_deeply(\@queries, $expected, 'Basic find()');

{
   # Internal, fragile test!
   is_deeply(
      $pl->{_reasons_for_matching}->{$matching_query},
      [ 'Exceeds busy time', 'Query matches Command spec', 'Query matches Info spec', ],
      "_reasons_for_matching works"
   );
}

%find_spec = (
   busy_time    => 1,
   ignore => {
      User     => qr/^system.user$/,
      State    => qr/Locked/,
      Command  => qr/Binlog Dump/,
   },
   match => {
   },
);

@queries = $pl->find(
   [  {  'Time'    => '488',
         'Command' => 'Sleep',
         'db'      => undef,
         'Id'      => '7',
         'Info'    => undef,
         'User'    => 'msandbox',
         'State'   => '',
         'Host'    => 'localhost'
      },
   ],
   %find_spec,
);

is(scalar(@queries), 0, 'Did not find any query');

%find_spec = (
   busy_time    => undef,
   idle_time    => 15,
   ignore => {
   },
   match => {
   },
);
is_deeply(
   [
      $pl->find(
         $rsp->parse(load_file('t/lib/samples/pl/recset003.txt')),
         %find_spec,
      )
   ],
   [
      {
         Id    => '29392005',
         User  => 'remote',
         Host  => '1.2.3.148:49718',
         db    => 'happy',
         Command => 'Sleep',
         Time  => '17',
         State => undef,
         Info  => undef,
      }
   ],
   'idle_time'
);

%find_spec = (
   match => { User => 'msandbox' },
);
@queries = $pl->find(
   $rsp->parse(load_file('t/lib/samples/pl/recset008.txt')),
   %find_spec,
);
ok(
   @queries == 0,
   "Doesn't match replication thread by default"
);

%find_spec = (
   replication_threads => 1,
   match => { User => 'msandbox' },
);
@queries = $pl->find(
   $rsp->parse(load_file('t/lib/samples/pl/recset008.txt')),
   %find_spec,
);
ok(
   @queries == 1,
   "Matches replication thread"
);

# ###########################################################################
# Find "all".
# ###########################################################################
%find_spec = (
   all => 1,
);
@queries = $pl->find(
   $rsp->parse(load_file('t/lib/samples/pl/recset002.txt')),
   %find_spec,
);

is_deeply(
   \@queries,
   $rsp->parse(load_file('t/lib/samples/pl/recset002.txt')),
   "Find all queries"
);

%find_spec = (
   all => 1,
   ignore => { Info => 'foo1' },
);
@queries = $pl->find(
   $rsp->parse(load_file('t/lib/samples/pl/recset002.txt')),
   %find_spec,
);

is_deeply(
   \@queries,
   [
      {
         Id      => '2',
         User    => 'user1',
         Host    => '1.2.3.4:5455',
         db      => 'foo',
         Command => 'Query',
         Time    => '5',
         State   => 'Locked',
         Info    => 'select * from foo2;',
      }
   ],
   "Find all queries that aren't ignored"
);

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/923896
# #############################################################################

%find_spec = (
   busy_time => 1,
   ignore    => {},
   match     => {},
);
my $proc = {  'Time'    => undef,
         'Command' => 'Query',
         'db'      => undef,
         'Id'      => '7',
         'Info'    => undef,
         'User'    => 'msandbox',
         'State'   => '',
         'Host'    => 'localhost'
      };

local $@;
eval { $pl->find([$proc], %find_spec) };
ok !$@,
 "Bug 923896: NULL Time in processlist doesn't fail for busy_time+Command=Query";

delete $find_spec{busy_time};
$find_spec{idle_time} = 1;
$proc->{Command}   = 'Sleep';

local $@;
eval { $pl->find([$proc], %find_spec) };
ok !$@,
 "Bug 923896: NULL Time in processlist doesn't fail for idle_time+Command=Sleep";

# #############################################################################
# NULL STATE doesn't generate warnings
# https://bugs.launchpad.net/percona-toolkit/+bug/821703
# #############################################################################

$procs = [
   [ [1, 'unauthenticated user', 'localhost', undef, 'Connect', 7,
    'some state', 1] ],
   [ [1, 'unauthenticated user', 'localhost', undef, 'Connect', 8,
    undef, 2] ],
],

eval {
   parse_n_times(
      2,
      code  => sub {
         return shift @$procs;
      },
      time  => Transformers::unix_timestamp('2001-01-01 00:05:00'),
   );
};

is(
   $EVAL_ERROR,
   '',
   "NULL STATE shouldn't cause warnings"
);

# #############################################################################
# Extra processlist fields are ignored and don't cause errors
# https://bugs.launchpad.net/percona-toolkit/+bug/883098
# #############################################################################

$procs = [
   [ [1, 'unauthenticated user', 'localhost', undef, 'Connect', 7,
    'some state', 1, 0, 0, 1] ],
   [ [1, 'unauthenticated user', 'localhost', undef, 'Connect', 8,
    undef, 2, 1, 2, 0] ],
],

eval {
   parse_n_times(
      2,
      code  => sub {
         return shift @$procs;
      },
      time  => Transformers::unix_timestamp('2001-01-01 00:05:00'),
   );
};

is(
   $EVAL_ERROR,
   '',
   "Extra processlist fields don't cause errors"
);
# #############################################################################
# Done.
# #############################################################################
done_testing;
