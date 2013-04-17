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
use EventAggregator;
use QueryParser;
use SlowLogParser;
use BinaryLogParser;
use Transformers;
use PerconaTest;

my $qr = new QueryRewriter();
my $qp = new QueryParser();
my $p  = new SlowLogParser();
my $bp = new BinaryLogParser();
my ( $result, $events, $ea, $expected );

$ea = new EventAggregator(
   groupby    => 'fingerprint',
   worst      => 'Query_time',
   attributes => {
      Query_time => [qw(Query_time)],
      user       => [qw(user)],
      ts         => [qw(ts)],
      Rows_sent  => [qw(Rows_sent)],
   },
);

isa_ok( $ea, 'EventAggregator' );

$events = [
   {  cmd           => 'Query',
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

$result = {
   'select id from users where name=?' => {
      Query_time => {
         min => '0.000652',
         max => '0.000682',
         all => {
            133 => 1,
            134 => 1,
         },
         sum => '0.001334',
         cnt => 2,
      },
      user => {
         unq => {
            bob  => 1,
            root => 1
         },
         min => 'bob',
         max => 'root',
         cnt => 2,
      },
      ts => {
         min => '071015 21:43:52',
         max => '071015 21:43:52',
         unq => { '071015 21:43:52' => 1, },
         cnt => 1,
      },
      Rows_sent => {
         min => 1,
         max => 1,
         all => {
            284 => 2,
         },
         sum => 2,
         cnt => 2,
      }
   },
   'insert ignore into articles (id, body,)values(?+)' => {
      Query_time => {
         min => '0.001943',
         max => '0.001943',
         all => {
            156 => 1,
         },
         sum => '0.001943',
         cnt => 1,
      },
      user => {
         unq => { root => 1 },
         min => 'root',
         max => 'root',
         cnt => 1,
      },
      ts => {
         min => '071015 21:43:52',
         max => '071015 21:43:52',
         unq => { '071015 21:43:52' => 1, },
         cnt => 1,
      },
      Rows_sent => {
         min => 0,
         max => 0,
         all => {
            0 => 1,
         },
         sum => 0,
         cnt => 1,
      }
   }
};

foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}

is_deeply( $ea->results->{classes},
   $result, 'Simple fingerprint aggregation' );

is_deeply(
   $ea->results->{samples},
   {
      'select id from users where name=?' => {
         ts            => '071015 21:43:52',
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
         fingerprint   => 'select id from users where name=?',
      },
      'insert ignore into articles (id, body,)values(?+)' => {
         ts   => '071015 21:43:52',
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
         fingerprint   => 'insert ignore into articles (id, body,)values(?+)',
      },
   },
   'Worst-in-class samples',
);

is_deeply(
   $ea->attributes,
   {  Query_time => 'num',
      user       => 'string',
      ts         => 'string',
      Rows_sent  => 'num',
   },
   'Found attribute types',
);

# Test with a nonexistent 'worst' attribute.
$ea = new EventAggregator(
   groupby    => 'fingerprint',
   worst      => 'nonexistent',
   attributes => {
      Query_time => [qw(Query_time)],
      user       => [qw(user)],
      ts         => [qw(ts)],
      Rows_sent  => [qw(Rows_sent)],
   },
);

foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}

is_deeply(
   $ea->results->{samples},
   {
      'select id from users where name=?' => {
         cmd           => 'Query',
         user          => 'root',
         host          => 'localhost',
         ip            => '',
         arg           => "SELECT id FROM users WHERE name='foo'",
         Query_time    => '0.000652',
         Lock_time     => '0.000109',
         Rows_sent     => 1,
         Rows_examined => 1,
         pos_in_log    => 0,
         fingerprint   => 'select id from users where name=?',
      },
      'insert ignore into articles (id, body,)values(?+)' => {
         ts   => '071015 21:43:52',
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
         fingerprint   => 'insert ignore into articles (id, body,)values(?+)',
      },
   },
   'Worst-in-class samples default to the first event seen',
);

$result = {
   Query_time => {
      min => '0.000652',
      max => '0.001943',
      sum => '0.003277',
      cnt => 3,
      all => {
         133 => 1,
         134 => 1,
         156 => 1,
      },
   },
   user => {
      min => 'bob',
      max => 'root',
      cnt => 3,
   },
   ts => {
      min => '071015 21:43:52',
      max => '071015 21:43:52',
      cnt => 2,
   },
   Rows_sent => {
      min => 0,
      max => 1,
      sum => 2,
      cnt => 3,
      all => {
         0   => 1, 
         284 => 2,
      },
   },
};

is_deeply( $ea->results->{globals},
   $result, 'Simple fingerprint aggregation all' );

# #############################################################################
# Test grouping on user
# #############################################################################
$ea = new EventAggregator(
   groupby    => 'user',
   worst      => 'Query_time',
   attributes => {
      Query_time => [qw(Query_time)],
      user       => [qw(user)], # It should ignore the groupby attribute
      ts         => [qw(ts)],
      Rows_sent  => [qw(Rows_sent)],
   },
);

$result = {
   classes => {
      bob => {
         ts => {
            min => '071015 21:43:52',
            max => '071015 21:43:52',
            unq => { '071015 21:43:52' => 1 },
            cnt => 1
         },
         Query_time => {
            min    => '0.000682',
            max    => '0.000682',
            all => {
               134 => 1,
            },
            sum => '0.000682',
            cnt => 1
         },
         Rows_sent => {
            min => 1,
            max => 1,
            all => {
               284 => 1,
            },
            sum => 1,
            cnt => 1
         }
      },
      root => {
         ts => {
            min => '071015 21:43:52',
            max => '071015 21:43:52',
            unq => { '071015 21:43:52' => 1 },
            cnt => 1
         },
         Query_time => {
            min    => '0.000652',
            max    => '0.001943',
            all => {
               133 => 1,
               156 => 1,
            },
            sum => '0.002595',
            cnt => 2
         },
         Rows_sent => {
            min => 0,
            max => 1,
            all => {
               0   => 1,
               284 => 1,
            },
            sum => 1,
            cnt => 2
         }
      }
   },
   samples => {
      bob => {
         cmd           => 'Query',
         arg           => 'SELECT id FROM users WHERE name=\'bar\'',
         ip            => '',
         ts            => '071015 21:43:52',
         fingerprint   => 'select id from users where name=?',
         host          => 'localhost',
         pos_in_log    => 5,
         Rows_examined => 2,
         user          => 'bob',
         Query_time    => '0.000682',
         Lock_time     => '0.000201',
         Rows_sent     => 1
      },
      root => {
         cmd => 'Query',
         arg =>
            'INSERT IGNORE INTO articles (id, body,)VALUES(3558268,\'sample text\')',
         ip => '',
         ts => '071015 21:43:52',
         fingerprint =>
            'insert ignore into articles (id, body,)values(?+)',
         host          => 'localhost',
         pos_in_log    => 1,
         Rows_examined => 0,
         user          => 'root',
         Query_time    => '0.001943',
         Lock_time     => '0.000145',
         Rows_sent     => 0
      },
   },
   globals => {
      ts => {
         min => '071015 21:43:52',
         max => '071015 21:43:52',
         cnt => 2
      },
      Query_time => {
         min => '0.000652',
         max => '0.001943',
         all => {
            133 => 1,
            134 => 1,
            156 => 1,
         },
         sum => '0.003277',
         cnt => 3
      },
      Rows_sent => {
         min => 0,
         max => 1,
         all => {
            0   => 1,
            284 => 2,
         },
         sum => 2,
         cnt => 3
      }
   }
};

foreach my $event (@$events) {
   $ea->aggregate($event);
}

is_deeply( $ea->results, $result, 'user aggregation' );

is($ea->type_for('Query_time'), 'num', 'Query_time is numeric');
$ea->calculate_statistical_metrics();
is_deeply(
   $ea->metrics(
      where  => 'bob',
      attrib => 'Query_time',
   ),
   {  pct     => 1/3,
      sum     => '0.000682',
      cnt     => 1,
      min     => '0.000682',
      max     => '0.000682',
      avg     => '0.000682',
      median  => '0.000682',
      stddev  => 0,
      pct_95  => '0.000682',
   },
   'Got simple hash of metrics from metrics()',
);

is_deeply(
   $ea->metrics(
      where  => 'foofoofoo',
      attrib => 'doesnotexist',
   ),
   {  pct     => 0,
      sum     => undef,
      cnt     => undef,
      min     => undef,
      max     => undef,
      avg     => 0,
      median  => 0,
      stddev  => 0,
      pct_95  => 0,
   },
   'It does not crash on metrics()',
);

# #############################################################################
# Test buckets.
# #############################################################################

# Given an arrayref of vals, returns an arrayref and hashref of those
# vals suitable for passing to calculate_statistical_metrics().
sub bucketize {
   my ( $vals, $as_hashref ) = @_;
   my $bucketed;
   if ( $as_hashref ) {
      $bucketed = {};
   }
   else {
      $bucketed = [ map { 0 } (0..999) ]; # TODO: shouldn't hard code this
   }
   my ($sum, $max, $min);
   $max = $min = $vals->[0];
   foreach my $val ( @$vals ) {
      if ( $as_hashref ) {
         $bucketed->{ EventAggregator::bucket_idx($val) }++;
      }
      else {
         $bucketed->[ EventAggregator::bucket_idx($val) ]++;
      }
      $max = $max > $val ? $max : $val;
      $min = $min < $val ? $min : $val;
      $sum += $val;
   }
   return $bucketed, { sum => $sum, max => $max, min => $min, cnt => scalar @$vals};
}

sub test_bucket_val {
   my ( $bucket, $val ) = @_;
   my $msg = sprintf 'bucket %d equals %.9f', $bucket, $val;
   cmp_ok(
      sprintf('%.9f', EventAggregator::bucket_value($bucket)),
      '==',
      $val,
      $msg
   );
   return;
}

sub test_bucket_idx {
   my ( $val, $bucket ) = @_;
   my $msg = sprintf 'val %.8f goes in bucket %d', $val, $bucket;
   cmp_ok(
      EventAggregator::bucket_idx($val),
      '==',
      $bucket,
      $msg
   );
   return;
}

test_bucket_idx(0, 0);
test_bucket_idx(0.0000001, 0);  # < MIN_BUCK (0.000001)
test_bucket_idx(0.000001, 1);   # = MIN_BUCK
test_bucket_idx(0.00000104, 1); # last val in bucket 1
test_bucket_idx(0.00000105, 2); # first val in bucket 2
test_bucket_idx(1, 284);
test_bucket_idx(2, 298);
test_bucket_idx(3, 306);
test_bucket_idx(4, 312);
test_bucket_idx(5, 317);
test_bucket_idx(6, 320);
test_bucket_idx(7, 324);
test_bucket_idx(8, 326);
test_bucket_idx(9, 329);
test_bucket_idx(20, 345);
test_bucket_idx(97.356678643, 378);
test_bucket_idx(100, 378);

#TODO: {
#   local $TODO = 'probably a float precision limitation';
#   test_bucket_idx(1402556844201353.5, 999); # first val in last bucket
#};

test_bucket_idx(9000000000000000.0, 999);

# These vals are rounded to 9 decimal places, otherwise we'll have
# problems with Perl returning stuff like 1.025e-9.
test_bucket_val(0, 0);
test_bucket_val(1,   0.000001000);
test_bucket_val(2,   0.000001050);
test_bucket_val(3,   0.000001103);
test_bucket_val(10,  0.000001551);
test_bucket_val(100, 0.000125239);
test_bucket_val(999, 1402556844201353.5);

is_deeply(
   [ bucketize( [ 2, 3, 6, 4, 8, 9, 1, 1, 1, 5, 4, 3, 1 ] ) ],
   [  [  ( map {0} ( 0 .. 283 ) ),
         4, # 1 -> 284
         ( map {0} ( 285 .. 297 ) ),
         1, # 2 -> 298
         ( map {0} ( 299 .. 305 ) ),
         2, # 3 -> 306
         ( map {0} ( 307 .. 311 ) ),
         2,             # 4 -> 312
         0, 0, 0, 0,    # 313, 314, 315, 316,
         1,             # 5 -> 317
         0, 0,          # 318, 319
         1,             # 6 -> 320
         0, 0, 0, 0, 0, # 321, 322, 323, 324, 325
         1,             # 8 -> 326
         0, 0,          # 327, 328
         1,             # 9 -> 329
         ( map {0} ( 330 .. 999 ) ),
      ],
      {  sum => 48,
         max => 9,
         min => 1,
         cnt => 13,
      },
   ],
   'Bucketizes values (values -> buckets)',
);

is_deeply(
   [ EventAggregator::buckets_of() ],
   [
      ( map {0} (0..47)    ),
      ( map {1} (48..94)   ),
      ( map {2} (95..141)  ),
      ( map {3} (142..188) ),
      ( map {4} (189..235) ),
      ( map {5} (236..283) ),
      ( map {6} (284..330) ),
      ( map {7} (331..999) )
   ],
   '8 buckets of base 10'
);

# #############################################################################
# Test statistical metrics: 95%, stddev, and median
# #############################################################################

$result = $ea->_calc_metrics(
   bucketize( [ 2, 3, 6, 4, 8, 9, 1, 1, 1, 5, 4, 3, 1 ], 1 ) );
# The above bucketize will be bucketized as:
# VALUE  BUCKET  VALUE        RANGE                       N VALS  SUM
# 1      248     0.992136979  [0.992136979, 1.041743827)  4       3.968547916
# 2      298     1.964363355  [1.964363355, 2.062581523)  1       1.964363355
# 3      306     2.902259332  [2.902259332, 3.047372299)  2       5.804518664
# 4      312     3.889305079  [3.889305079, 4.083770333)  2       7.778610158
# 5      317     4.963848363  [4.963848363, 5.212040781)  1       4.963848363
# 6      320     5.746274961  [5.746274961, 6.033588710)  1       5.746274961
# 8      326     7.700558026  [7.700558026, 8.085585927)  1       7.700558026
# 9      329     8.914358484  [8.914358484, 9.360076409)  1       8.914358484
#                                                                 -----------
#                                                                 46.841079927
# I have hand-checked these values and they are correct.
is_deeply(
   $result,
   {
      stddev => 2.51982318221967,
      median => 2.90225933213165,
      cutoff => 12,
      pct_95 => 7.70055802567889,
   },
   'Calculates statistical metrics'
);

$result = $ea->_calc_metrics(
   bucketize( [ 1, 1, 1, 1, 2, 3, 4, 4, 4, 4, 6, 8, 9 ], 1 ) );
# The above bucketize will be bucketized as:
# VALUE  BUCKET  VALUE        RANGE                       N VALS
# 1      248     0.992136979  [0.992136979, 1.041743827)  4
# 2      298     1.964363355  [1.964363355, 2.062581523)  1
# 3      306     2.902259332  [2.902259332, 3.047372299)  1
# 4      312     3.889305079  [3.889305079, 4.083770333)  4
# 6      320     5.746274961  [5.746274961, 6.033588710)  1
# 8      326     7.700558026  [7.700558026, 8.085585927)  1
# 9      329     8.914358484  [8.914358484, 9.360076409)  1
#
# I have hand-checked these values and they are correct.
is_deeply(
   $result,
   {
      stddev => 2.48633263817885,
      median => 3.88930507895285,
      cutoff => 12,
      pct_95 => 7.70055802567889,
   },
   'Calculates median when it is halfway between two elements',
);

# This is a special case: only two values, widely separated.  The median should
# be exact (because we pass in min/max) and the stdev should never be bigger
# than half the difference between min/max.
$result = $ea->_calc_metrics(
   bucketize( [ 0.000002, 0.018799 ], 1 ) );
is_deeply(
   $result,
   {  stddev => 0.0132914861659635,
      median => 0.0094005,
      cutoff => 2,
      pct_95 => 0.018799,
   },
   'Calculates stats for two-element special case',
);

$result = $ea->_calc_metrics(undef);
is_deeply(
   $result,
   {  stddev => 0,
      median => 0,
      cutoff => undef,
      pct_95 => 0,
   },
   'Calculates statistical metrics for undef array'
);

$result = $ea->_calc_metrics( {}, 1 );
is_deeply(
   $result,
   {  stddev => 0,
      median => 0,
      cutoff => undef,
      pct_95 => 0,
   },
   'Calculates statistical metrics for empty hashref'
);

$result = $ea->_calc_metrics( { 1 => 2 }, {} );
is_deeply(
   $result,
   {  stddev => 0,
      median => 0,
      cutoff => undef,
      pct_95 => 0,
   },
   'Calculates statistical metrics for when $stats missing'
);

$result = $ea->_calc_metrics( bucketize( [0.9], 1 ) );
is_deeply(
   $result,
   {  stddev => 0,
      median => 0.9,
      cutoff => 1,
      pct_95 => 0.9,
   },
   'Calculates statistical metrics for 1 value'
);

# #############################################################################
# Make sure it doesn't die when I try to parse an event that doesn't have an
# expected attribute.
# #############################################################################
eval { $ea->aggregate( { fingerprint => 'foo' } ); };
is( $EVAL_ERROR, '', "Handles an undef attrib OK" );

# #############################################################################
# Issue 184: db OR Schema
# #############################################################################
$ea = new EventAggregator(
   groupby => 'arg',
   attributes => {
      db => [qw(db Schema)],
   },
   worst => 'foo',
);

$events = [
   {  arg    => "foo1",
      Schema => 'db1',
   },
   {  arg => "foo2",
      db  => 'db1',
   },
];
foreach my $event (@$events) {
   $ea->aggregate($event);
}

is( $ea->results->{classes}->{foo1}->{db}->{min},
   'db1', 'Gets Schema for db|Schema (issue 184)' );

is( $ea->results->{classes}->{foo2}->{db}->{min},
   'db1', 'Gets db for db|Schema (issue 184)' );

# #############################################################################
# Make sure large values are kept reasonable.
# #############################################################################
$ea = new EventAggregator(
   attributes   => { Rows_read => [qw(Rows_read)], },
   attrib_limit => 1000,
   worst        => 'foo',
   groupby      => 'arg',
);

$events = [
   {  arg       => "arg1",
      Rows_read => 4,
   },
   {  arg       => "arg2",
      Rows_read => 4124524590823728995,
   },
   {  arg       => "arg1",
      Rows_read => 4124524590823728995,
   },
];

foreach my $event (@$events) {
   $ea->aggregate($event);
}

$result = {
   classes => {
      'arg1' => {
         Rows_read => {
            min => 4,
            max => 4,
            all => {
               312 => 2,
            },
            sum    => 8,
            cnt    => 2,
            'last' => 4,
         }
      },
      'arg2' => {
         Rows_read => {
            min => 0,
            max => 0,
            all => {
               0 => 1,
            },
            sum    => 0,
            cnt    => 1,
            'last' => 0,
         }
      },
   },
   globals => {
      Rows_read => {
         min => 0, # Because 'last' is only kept at the class level
         max => 4,
         all => {
            0   => 1,
            312 => 2,
         },
         sum => 8,
         cnt => 3,
      },
   },
   samples => {
      arg1 => {
         arg       => "arg1",
         Rows_read => 4,
      },
      arg2 => {
         arg       => "arg2",
         Rows_read => 4124524590823728995,
      },
   },
};

is_deeply( $ea->results, $result, 'Limited attribute values', );

# #############################################################################
# For issue 171, the enhanced --top syntax, we need to pick events by complex
# criteria.  It's too messy to do with a log file, so we'll do it with an event
# generator function.
# #############################################################################
{
   my $i = 0;
   my @event_specs = (
      # fingerprint, time, count; 1350 seconds total
      [ 'event0', 10, 1   ], # An outlier, but happens once
      [ 'event1', 10, 5   ], # An outlier, but not in top 95%
      [ 'event2', 2,  500 ], # 1000 seconds total
      [ 'event3', 1,  500 ], # 500  seconds total
      [ 'event4', 1,  300 ], # 300  seconds total
   );
   sub generate_event {
      START:
      if ( $i >= $event_specs[0]->[2] ) {
         shift @event_specs;
         $i = 0;
      }
      $i++;
      return undef unless @event_specs;
      return {
         fingerprint => $event_specs[0]->[0],
         Query_time  => $event_specs[0]->[1],
      };
   }
}

$ea = new EventAggregator(
   groupby    => 'fingerprint',
   worst      => 'foo',
   attributes => {
      Query_time => [qw(Query_time)],
   },
);

while ( my $event = generate_event() ) {
   $ea->aggregate($event);
}
$ea->calculate_statistical_metrics();
my $chosen;
my $other;

($chosen, $other) = $ea->top_events(
   groupby => 'fingerprint',
   attrib  => 'Query_time',
   orderby => 'sum',
   total   => 1300,
   count   => 2,               # Get event2/3 but not event4
   # Or outlier events that usually take > 5s to execute and happened > 3 times
   ol_attrib => 'Query_time',
   ol_limit  => 5,
   ol_freq   => 3,
);

is_deeply(
   $chosen,
   [
      [qw(event2 top 1)],
      [qw(event3 top 2)],
      [qw(event1 outlier 4)],
   ],
   'Got top events'
);

is_deeply(
   $other,
   [
      [qw(event4 misc 3)],
      [qw(event0 misc 5)],
   ],
   "Got other, non-top events"
);

($chosen, $other) = $ea->top_events(
   groupby => 'fingerprint',
   attrib  => 'Query_time',
   orderby => 'sum',
   total   => 1300,
   count   => 2,               # Get event2/3 but not event4
   # Or outlier events that usually take > 5s to execute
   ol_attrib => 'Query_time',
   ol_limit  => 5,
   ol_freq   => undef,
);

is_deeply(
   $chosen,
   [
      [qw(event2 top 1)],
      [qw(event3 top 2)],
      [qw(event1 outlier 4)],
      [qw(event0 outlier 5)],
   ],
   'Got top events with outlier' );

# Try to make it fail
eval {
   $ea->aggregate({foo         => 'FAIL'});
   $ea->aggregate({fingerprint => 'FAIL'});
   # but not this one -- the caller should eval to catch this.
   # $ea->aggregate({fingerprint => 'FAIL2', Query_time => 'FAIL' });
   ($chosen, $other) = $ea->top_events(
      groupby => 'fingerprint',
      attrib  => 'Query_time',
      orderby => 'sum',
      count   => 2,
   );
};
is($EVAL_ERROR, '', 'It handles incomplete/malformed events');

$events = [
   {  Query_time    => '0.000652',
      arg           => 'select * from sakila.actor join sakila.film_actor using(actor_id)',
   },
   {  Query_time    => '1.000652',
      arg           => 'select * from sakila.actor',
   },
   {  Query_time    => '2.000652',
      arg           => 'select * from sakila.actor join sakila.film_actor using(actor_id)',
   },
   {  Query_time    => '0.000652',
      arg           => 'select * from sakila.actor',
   },
];

$ea = new EventAggregator(
   groupby    => 'tables',
   worst      => 'foo',
   attributes => {
      Query_time => [qw(Query_time)],
   },
);

foreach my $event ( @$events ) {
   $event->{tables} = [ $qp->get_tables($event->{arg}) ];
   $ea->aggregate($event);
}

is_deeply(
   $ea->results,
   {
      classes => {
         'sakila.actor' => {
            Query_time => {
               min => '0.000652',
               max => '2.000652',
               all => {
                  133 => 2,
                  284 => 1,
                  298 => 1,
               },
               sum => '3.002608',
               cnt => 4,
            },
         },
         'sakila.film_actor' => {
            Query_time => {
               min => '0.000652',
               max => '2.000652',
               all => {
                  133 => 1,
                  298 => 1,
               },
               sum => '2.001304',
               cnt => 2,
            },
         },
      },
      globals => {
         Query_time => {
            min => '0.000652',
            max => '2.000652',
            all => {
               133 => 3,
               284 => 1,
               298 => 2,
            },
            sum => '5.003912',
            cnt => 6,
         },
      },
      samples => {
         'sakila.actor' => {
            Query_time    => '0.000652',
            arg           => 'select * from sakila.actor join sakila.film_actor using(actor_id)',
            tables        => [qw(sakila.actor sakila.film_actor)],
         },
         'sakila.film_actor' => {
            Query_time    => '0.000652',
            arg           => 'select * from sakila.actor join sakila.film_actor using(actor_id)',
            tables        => [qw(sakila.actor sakila.film_actor)],
         },
      },
   },
   'Aggregation by tables',
);

# Event attribute with space in name.
$ea = new EventAggregator(
   groupby    => 'fingerprint',
   worst      => 'Query time',
   attributes => {
      'Query time' => ['Query time'],
   },
);
$events = {
   fingerprint  => 'foo',
   'Query time' => 123,
};
$ea->aggregate($events);
is(
   $ea->results->{classes}->{foo}->{'Query time'}->{min},
   123,
   'Aggregates attributes with spaces in their names'
);

# Make sure types can be hinted directly.
$ea = new EventAggregator(
   groupby    => 'fingerprint',
   worst      => 'Query time',
   attributes => {
      'Query time' => ['Query time'],
      'Schema'     => ['Schema'],
   },
   type_for => {
      Query_time => 'string',
   },
);
$events = {
   fingerprint  => 'foo',
   'Query_time' => 123,
   'Schema'     => '',
};
$ea->aggregate($events);
is(
   $ea->type_for('Query_time'),
   'string',
   'Query_time type can be hinted directly',
);

# #############################################################################
# Issue 323: mk-query-digest does not properly handle logs with an empty Schema:
# #############################################################################
$ea = new EventAggregator(
   groupby    => 'fingerprint',
   worst      => 'Query time',
   attributes => {
      'Query time' => ['Query time'],
      'Schema'     => ['Schema'],
   },
);
$events = {
   fingerprint  => 'foo',
   'Query time' => 123,
   'Schema'     => '',
};
$ea->aggregate($events);
is(
   $ea->type_for('Schema'),
   'string',
   'Empty Schema: (issue 323)'
);

# #############################################################################
# Issue 321: mk-query-digest stuck in infinite loop while processing log
# #############################################################################

my $bad_vals =
   [  580, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 25, 0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0,
      0,   0, 0, 0, 0, 0, 0, 0, 0, 0
   ];

my $bad_event = {
   min => 0,
   max => 1,
   last => 1,
   sum => 25,
   cnt => 605
};

# Converted for http://code.google.com/p/maatkit/issues/detail?id=866
my $bad_vals_hashref = {};
$bad_vals_hashref->{$_} = $bad_vals->[$_] for 0..999;

$result = $ea->_calc_metrics($bad_vals_hashref, $bad_event);
is_deeply(
   $result,
   {
      stddev => 0.1974696076416,
      median => 0,
      pct_95 => 0,
      cutoff => 574,
   },
   'statistical metrics with mostly zero values'
);

# #############################################################################
# Issue 332: mk-query-digest crashes on sqrt of negative number
# #############################################################################
$bad_vals = {
   499 => 12,
};
$bad_event = {
   min  => 36015,
   max  => 36018,
   last => 0,
   sum  => 432212,
   cnt  => 12,
};

$result = $ea->_calc_metrics($bad_vals, $bad_event);
is_deeply(
   $result,
   {
      stddev => 0,
      median => 35667.3576664115,
      pct_95 => 35667.3576664115,
      cutoff => 11,
   },
   'float math with big number (issue 332)'
);

$bad_vals = {
   799 => 9,
};
$bad_event = {
   min  => 36015, 
   max  => 36018,
   last => 0,
   sum  => 432212,
   cnt  => 9,
};

$result = $ea->_calc_metrics($bad_vals, $bad_event);
is_deeply(
   $result,
   {
      stddev => 0,
      median => 81107433250.8976,
      pct_95 => 81107433250.8976,
      cutoff => 9,
   },
   'float math with bigger number (issue 332)'
);

$ea->reset_aggregated_data();
is_deeply(
   $ea->results(),
   {
      classes => {
         foo => {
            Schema       => {},
            'Query time' => {},
         }
      },
      globals => {
         Schema       => {},
         'Query time' => {},
      },
      samples => {},
   },
   'Reset works');

# #############################################################################
# Issue 396: Make mk-query-digest detect properties of events to output
# #############################################################################
$ea = new EventAggregator(
   groupby       => 'arg',
   worst         => 'Query_time',
);
$events = [
   {  arg        => "foo",
      Schema     => 'db1',
      Query_time => '1.000000',
      other_prop => 'trees',
   },
   {  arg        => "foo",
      Schema     => 'db1',
      Query_time => '2.000000',
      new_prop   => 'The quick brown fox jumps over the lazy dog',
   },
];
foreach my $event ( @$events ) {
   $ea->aggregate($event);
}
is_deeply(
   $ea->results(),
   {
      samples => {
       foo => {
         Schema => 'db1',
         new_prop => 'The quick brown fox jumps over the lazy dog',
         arg => 'foo',
         Query_time => '2.000000'
       }
      },
      classes => {
       foo => {
         Schema => {
           min => 'db1',
           max => 'db1',
           unq => {
             db1 => 2
           },
           cnt => 2
         },
         other_prop => {
           min => 'trees',
           max => 'trees',
           unq => {
             trees => 1
           },
           cnt => 1
         },
         new_prop => {
           min => 'The quick brown fox jumps over the lazy dog',
           max => 'The quick brown fox jumps over the lazy dog',
           unq => {
            'The quick brown fox jumps over the lazy dog' => 1,
           },
           cnt => 1,
         },
         Query_time => {
           min => '1.000000',
           max => '2.000000',
           all => {
              284 => 1,
              298 => 1,
           },
           sum => 3,
           cnt => 2
         }
       }
      },
      globals => {
       Schema => {
         min => 'db1',
         max => 'db1',
         cnt => 2
       },
       other_prop => {
         min => 'trees',
         max => 'trees',
         cnt => 1
       },
       new_prop => {
         min => 'The quick brown fox jumps over the lazy dog',
         max => 'The quick brown fox jumps over the lazy dog',
         cnt => 1,
       },
       Query_time => {
         min => '1.000000',
         max => '2.000000',
         all => {
            284 => 1,
            298 => 1,
         },
         sum => 3,
         cnt => 2
       }
      }
   },
   'Auto-detect attributes if none given',
);

is_deeply(
   [ sort @{$ea->get_attributes()} ],
   [qw(Query_time Schema new_prop other_prop)],
   'get_attributes()',
);

is(
   $ea->events_processed(),
   2,
   'events_processed()'
);

my $only_query_time_results =  {
      samples => {
       foo => {
         Schema => 'db1',
         new_prop => 'The quick brown fox jumps over the lazy dog',
         arg => 'foo',
         Query_time => '2.000000'
       }
      },
      classes => {
       foo => {
         Query_time => {
           min => '1.000000',
           max => '2.000000',
           all => {
              284 => 1,
              298 => 1,
           },
           sum => 3,
           cnt => 2
         }
       }
      },
      globals => {
       Query_time => {
         min => '1.000000',
         max => '2.000000',
         all => {
            284 => 1,
            298 => 1,
         },
         sum => 3,
         cnt => 2
       }
      }
};

$ea = new EventAggregator(
   groupby    => 'arg',
   worst      => 'Query_time',
   attributes => {
      Query_time => [qw(Query_time)],
   },
);
foreach my $event ( @$events ) {
   $ea->aggregate($event);
}
is_deeply(
   $ea->results(),
   $only_query_time_results,
   'Do not auto-detect attributes if given explicit attributes',
);

$ea = new EventAggregator(
   groupby           => 'arg',
   worst             => 'Query_time',
   ignore_attributes => [ qw(new_prop other_prop Schema) ],
);
foreach my $event ( @$events ) {
   $ea->aggregate($event);
}
is_deeply(
   $ea->results(),
   $only_query_time_results,
   'Ignore some auto-detected attributes',
);

# #############################################################################
# Issue 458: mk-query-digest Use of uninitialized value in division (/) at
# line 3805.
# #############################################################################
$ea = new EventAggregator(
   groupby           => 'arg',
   worst             => 'Query_time',
);

# The real bug is in QueryReportFormatter, and there's nothing particularly
# interesting about this sample, but we just want to make sure that the
# timestamp prop shows up only in the one event.  The bug is that it appears
# to be in all events by the time we get to QueryReportFormatter.
is_deeply(
   parse_file('t/lib/samples/slowlogs/slow029.txt', $p, $ea),
   [
      {
       Schema => 'mysql',
       bytes => 11,
       db => 'mysql',
       cmd => 'Query',
       arg => 'show status',
       ip => '',
       Thread_id => '1530316',
       host => 'localhost',
       pos_in_log => 0,
       timestamp => '1241453102',
       Rows_examined => '249',
       user => 'root',
       Query_time => '4.352063',
       Rows_sent => '249',
       Lock_time => '0.000000'
      },
      {
       Schema => 'pro',
       bytes => 179,
       db => 'pro',
       cmd => 'Query',
       arg => 'SELECT * FROM `events`     WHERE (`events`.`id` IN (51118,51129,50893,50567,50817,50834,50608,50815,51023,50903,50820,50003,50890,50673,50596,50553,50618,51103,50578,50732,51021))',
       ip => '1.2.3.87',
       ts => '090504  9:07:24',
       Thread_id => '1695747',
       host => 'x03-s00342.x03.domain.com',
       pos_in_log => 206,
       Rows_examined => '26876',
       Query_time => '2.156031',
       user => 'dbuser',
       Rows_sent => '21',
       Lock_time => '0.000000'
      },
      {
       Schema => 'pro',
       bytes => 66,
       cmd => 'Query',
       arg => 'SELECT * FROM `users`     WHERE (email = NULL or new_email = NULL)',
       ip => '1.2.3.84',
       Thread_id => '1695268',
       host => 'x03-s00339.x03.domain.com',
       pos_in_log => 602,
       Rows_examined => '106242',
       user => 'dbuser',
       Query_time => '2.060030',
       Rows_sent => '0',
       Lock_time => '0.000000'
      },
   ],
   'slow029.txt events (issue 458)'
);

ok(
   !exists $ea->results->{samples}->{'SELECT * FROM `users`     WHERE (email = NULL or new_email = NULL)'}->{timestamp}
   && !exists $ea->results->{samples}->{'SELECT * FROM `events`     WHERE (`events`.`id` IN (51118,51129,50893,50567,50817,50834,50608,50815,51023,50903,50820,50003,50890,50673,50596,50553,50618,51103,50578,50732,51021))'}->{timestamp}
   && exists $ea->results->{samples}->{'show status'}->{timestamp},
   'props not auto-vivified (issue 458)',
);

# #############################################################################
# Issue 514: mk-query-digest does not create handler sub for new auto-detected
# attributes
# #############################################################################
$ea = new EventAggregator(
   groupby      => 'arg',
   worst        => 'Query_time',
);
# In slow030, event 180 is a new class with new attributes.
parse_file('t/lib/samples/slowlogs/slow030.txt', $p, $ea);
ok(
   exists $ea->{unrolled_for}->{InnoDB_rec_lock_wait},
   'Handler sub created for new attrib; default unroll_limit (issue 514)'
);
ok(
   exists $ea->{result_classes}->{'SELECT * FROM bar'}->{InnoDB_IO_r_bytes},
   'New event class has new attrib; default unroll_limit(issue 514)'
);

$ea = do {
   local $ENV{PT_QUERY_DIGEST_CHECK_ATTRIB_LIMIT} = 50;
   new EventAggregator(
      groupby      => 'arg',
      worst        => 'Query_time'
   );
};

parse_file('t/lib/samples/slowlogs/slow030.txt', $p, $ea);
ok(
   !exists $ea->{unrolled_for}->{InnoDB_rec_lock_wait},
   'Handler sub not created for new attrib; unroll_limit=50 (issue 514)'
);
ok(
   !exists $ea->{result_classes}->{'SELECT * FROM bar'}->{InnoDB_IO_r_bytes},
   'New event class has new attrib; default unroll_limit=50 (issue 514)'
);

# #############################################################################
# Check that broken Query_time are fixed (issue 234).
# #############################################################################
$events = [
   {  cmd           => 'Query',
      user          => 'root',
      host          => 'localhost',
      ip            => '',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '17.796870.000036',
      Lock_time     => '0.000000',
      Rows_sent     => 1,
      Rows_examined => 1,
      pos_in_log    => 0,
   },
];

$ea = new EventAggregator(
   groupby      => 'arg',
   worst        => 'Query_time',
);
foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}

is_deeply(
   $ea->results->{samples},
   {
      'SELECT id FROM users WHERE name=\'foo\'' => {
         Lock_time => '0.000000',
         Query_time => '17.796870',
         Rows_examined => 1,
         Rows_sent => 1,
         arg => 'SELECT id FROM users WHERE name=\'foo\'',
         cmd => 'Query',
         fingerprint => 'select id from users where name=?',
         host => 'localhost',
         ip => '',
         pos_in_log => 0,
         user => 'root'
      },
   },
   'Broken Query_time (issue 234)'
);

# #############################################################################
# Issue 607: mk-query-digest throws Possible unintended interpolation of
# @session in string
# #############################################################################
$ea = new EventAggregator(
   groupby      => 'arg',
   worst        => 'Query_time',
   unroll_limit => 1,
);
eval {
   parse_file('t/lib/samples/binlogs/binlog004.txt', $bp, $ea);
};
is(
   $EVAL_ERROR,
   '',
   'No error parsing binlog with @attribs (issue 607)'
);

# #############################################################################
# merge()
# #############################################################################
my $ea1 = new EventAggregator(
   groupby    => 'fingerprint',
   worst      => 'Query_time',
   attributes => {
      Query_time => [qw(Query_time)],
      user       => [qw(user)],
      ts         => [qw(ts)],
      Rows_sent  => [qw(Rows_sent)],
      Full_scan  => [qw(Full_scan)],
      ea1_only   => [qw(ea1_only)],
      ea2_only   => [qw(ea2_only)],
   },
);
my $ea2 = new EventAggregator(
   groupby    => 'fingerprint',
   worst      => 'Query_time',
   attributes => {
      Query_time => [qw(Query_time)],
      user       => [qw(user)],
      ts         => [qw(ts)],
      Rows_sent  => [qw(Rows_sent)],
      Full_scan  => [qw(Full_scan)],
      ea1_only   => [qw(ea1_only)],
      ea2_only   => [qw(ea2_only)],
   },
);

$events = [
   {  ts            => '071015 19:00:00',
      cmd           => 'Query',
      user          => 'root',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '0.000652',
      Rows_sent     => 1,
      pos_in_log    => 0,
      Full_scan     => 'No',
      ea1_only      => 5,
   },
];
foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea1->aggregate($event);
}

$events = [
   {  ts            => '071015 21:43:52',
      cmd           => 'Query',
      user          => 'bob',
      arg           => "SELECT id FROM users WHERE name='bar'",
      Query_time    => '0.000682',
      Rows_sent     => 2,
      pos_in_log    => 5,
      Full_scan     => 'Yes',
      ea2_only      => 7,
   }
];
foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea2->aggregate($event);
}

$result = {
   classes => {
      'select id from users where name=?' => {
         Query_time => {
            min => '0.000652',
            max => '0.000682',
            all => {
               133 => 1,
               134 => 1,
            },
            sum => '0.001334',
            cnt => 2,
         },
         user => {
            unq => {
               bob  => 1,
               root => 1
            },
            min => 'bob',
            max => 'root',
            cnt => 2,
         },
         ts => {
            min => '071015 19:00:00',
            max => '071015 21:43:52',
            cnt => 2,
            unq => {
               '071015 19:00:00' => 1,
               '071015 21:43:52' => 1,
            },
         },
         Rows_sent => {
            min => 1,
            max => 2,
            all => {
               284 => 1,
               298 => 1,
            },
            sum => 3,
            cnt => 2,
         },
         Full_scan => {
            cnt => 2,
            max => 1,
            min => 0,
            sum => 1,
            unq => {
               '0' => 1,
               '1' => 1,
            },
         },
         ea1_only => {
            min => '5',
            max => '5',
            all => { 317 => 1 },
            sum => '5',
            cnt => 1,
         },
         ea2_only => {
            min => '7',
            max => '7',
            all => { 324 => 1 },
            sum => '7',
            cnt => 1,
         },
      },
   },
   globals => {
      Query_time => {
         min => '0.000652',
         max => '0.000682',
         sum => '0.001334',
         cnt => 2,
         all => {
            133 => 1,
            134 => 1,
         },
      },
      user => {
         min => 'bob',
         max => 'root',
         cnt => 2,
      },
      ts => {
         min => '071015 19:00:00',
         max => '071015 21:43:52',
         cnt => 2,
      },
      Rows_sent => {
         min => 1,
         max => 2,
         sum => 3,
         cnt => 2,
         all => {
            284 => 1,
            298 => 1,
         },
      },
      Full_scan => {
         cnt => 2,
         max => 1,
         min => 0,
         sum => 1,
      },
      ea1_only => {
         min => '5',
         max => '5',
         all => { 317 => 1 },
         sum => '5',
         cnt => 1,
      },
      ea2_only => {
         min => '7',
         max => '7',
         all => { 324 => 1 },
         sum => '7',
         cnt => 1,
      },
   },
   samples => {
      'select id from users where name=?' => {
         ts            => '071015 21:43:52',
         cmd           => 'Query',
         user          => 'bob',
         arg           => "SELECT id FROM users WHERE name='bar'",
         Query_time    => '0.000682',
         Rows_sent     => 2,
         pos_in_log    => 5,
         fingerprint   => 'select id from users where name=?',
         Full_scan     => 'Yes',
         ea2_only      => 7,
      },
   },
};

my $ea3 = EventAggregator::merge($ea1, $ea2);

is_deeply(
   $ea3->results,
   $result,
   "Merge results"
);

# #############################################################################
# Special-case attribs called *_crc for mqd --variations.
# #############################################################################

# Any attrib called *_crc should be automatically treated as a string,
# so no need to specify type_for.
$ea = new EventAggregator(
   groupby => 'arg',
   worst   => 'Query_time',
);

# And _crc attribs should be % 1000 so there shouldn't be more than 1k of them.
for my $i ( 1001..2102 ) {
   $ea->aggregate(
      { arg        => 'foo',
        Query_time => 1,
        Foo_crc    => Transformers::crc32("string$i"),
      }
   );
}

my $crcs = $ea->results->{classes}->{foo}->{Foo_crc};
is(
   $crcs->{cnt},
   1102,
   "Aggregated all the CRCs"
);

# Some CRCs become the same value after mod 1000, those although
# there were more than 1k aggregated, no more than 1k should be saved.
cmp_ok(
   scalar keys %{$crcs->{unq}},
   '<=',
   1000,
   "Saved no more than 1_000 CRCs"
);

# #############################################################################
# Bug 821694: pt-query-digest doesn't recognize hex InnoDB txn IDs
# #############################################################################
$ea = new EventAggregator(
   groupby      => 'arg',
   worst        => 'Query_time',
   unroll_limit => 5,
   type_for     => {
      'InnoDB_trx_id' => 'string',
   },
);
parse_file('t/lib/samples/slowlogs/slow054.txt', $p, $ea);
is(
   $ea->{result_classes}->{'SELECT * FROM foo WHERE id=1'}->{InnoDB_trx_id}->{cnt},
   8,
   "Parse InnoDB_trx_id as string"
);

# #############################################################################
# Bug 924950: pt-query-digest --group-by db may crash profile report
# #############################################################################
$ea = new EventAggregator(
   groupby => 'Schema',
   worst   => 'Query_time',
);
parse_file('t/lib/samples/slowlogs/slow055.txt', $p, $ea);
my $m = $ea->metrics(where => '', attrib => 'Query_time');
is(
   $m->{cnt},
   3,
   "Metrics for '' attrib (bug 924950)"
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
done_testing;
exit;
