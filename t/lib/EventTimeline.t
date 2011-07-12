#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 3;

use Transformers;
use QueryRewriter;
use EventTimeline;
use PerconaTest;

my $qr = new QueryRewriter();
my ( $result, $events, $et, $expected );

$et = new EventTimeline(
   groupby    => [qw(fingerprint)],
   attributes => [qw(Query_time ts)],
);

$events = [
   {  cmd           => 'Query',
      ts            => '071015 21:43:52',
      user          => 'root',
      host          => 'localhost',
      ip            => '',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '0.000652',
      Lock_time     => '0.000109',
      Rows_sent     => 1,
      Rows_examined => 1,
      pos_in_log    => 0,
   },
   {  ts   => '071015 21:43:52',
      cmd  => 'Query',
      user => 'root',
      host => 'localhost',
      ip   => '',
      arg =>
         "INSERT IGNORE INTO articles (id, body,)VALUES(3558268,'sample text')",
      Query_time    => '0.001943',
      Lock_time     => '0.000145',
      Rows_sent     => 0,
      Rows_examined => 0,
      pos_in_log    => 1,
   },
   {  ts   => '071015 21:49:52',
      cmd  => 'Query',
      user => 'root',
      host => 'localhost',
      ip   => '',
      arg =>
         "INSERT IGNORE INTO articles (id, body,)VALUES(3558268,'sample text')",
      Query_time    => '0.001943',
      Lock_time     => '0.000145',
      Rows_sent     => 0,
      Rows_examined => 0,
      pos_in_log    => 1,
   },
   {  ts            => '071015 21:43:52',
      cmd           => 'Query',
      user          => 'bob',
      host          => 'localhost',
      ip            => '',
      arg           => "SELECT id FROM users WHERE name='bar'",
      Query_time    => '0.000682',
      Lock_time     => '0.000201',
      Rows_sent     => 1,
      Rows_examined => 2,
      pos_in_log    => 5,
   }
];

$result = [
   [  ['select id from users where name=?'],
      1,
      {  Query_time => {
            min => '0.000652',
            max => '0.000652',
            sum => '0.000652',
         },
         ts => {
            min => '071015 21:43:52',
            max => '071015 21:43:52',
         },
      },
   ],
   [  ['insert ignore into articles (id, body,)values(?+)'],
      2,
      {  Query_time => {
            min => '0.001943',
            max => '0.001943',
            sum => 0.001943 * 2,
         },
         ts => {
            min => '071015 21:43:52',
            max => '071015 21:49:52',
         },
      },
   ],
   [  ['select id from users where name=?'],
      1,
      {  Query_time => {
            min => '0.000682',
            max => '0.000682',
            sum => '0.000682',
         },
         ts => {
            min => '071015 21:43:52',
            max => '071015 21:43:52',
         },
      },
   ],
];

foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $et->aggregate($event);
}

is_deeply( $et->results,
   $result, 'Simple fingerprint aggregation' );

$expected = <<EOF;
# ########################################################################
# fingerprint report
# ########################################################################
# 2007-10-15 21:43:52    0:00   1 select id from users where name=?
# 2007-10-15 21:43:52   06:00   2 insert ignore into articles (id, body,)values(?+)
# 2007-10-15 21:43:52    0:00   1 select id from users where name=?
EOF

$result = '';
$et->report($et->results, sub { $result .= $_[0] });

$et->reset_aggregated_data();
is_deeply($et->results, [], 'reset_aggregated_data()');

is($result, $expected, 'Report for simple timeline');
