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
use EventAggregator;
use QueryRewriter;
use ReportFormatter;
use UpgradeReportFormatter;
use MaatkitTest;

my $result;
my $expected;
my ($meta_events, $events1, $events2, $meta_ea, $ea1, $ea2);

my $qr  = new QueryRewriter();
my $urf = new UpgradeReportFormatter();

sub aggregate {
   foreach my $event (@$meta_events) {
      $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
      $meta_ea->aggregate($event);
   }
   foreach my $event (@$events1) {
      $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
      $ea1->aggregate($event);
   }
   $ea1->calculate_statistical_metrics();
   foreach my $event (@$events2) {
      $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
      $ea2->aggregate($event);
   }
   $ea2->calculate_statistical_metrics(); 
}

$meta_ea = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'differences',
);
$ea1 = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
);
$ea2 = new EventAggregator(
   groupby => 'fingerprint',
   worst   => 'Query_time',
);

isa_ok($urf, 'UpgradeReportFormatter');

$events1 = [
   {
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '8.000652',
      pos_in_log    => 1,
      db            => 'test1',
      Errors        => 'No',
   },
   {
      cmd  => 'Query',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '1.001943',
      pos_in_log    => 2,
      db            => 'test1',
      Errors        => 'Yes',
   },
   {
      cmd           => 'Query',
      arg           => "SELECT id FROM users WHERE name='bar'",
      Query_time    => '1.000682',
      pos_in_log    => 5,
      db            => 'test1',
      Errors        => 'No',
   },
];
$events2 = $events1;
$meta_events = [
   {
      arg => "SELECT id FROM users WHERE name='bar'",
      differences          => 0,
      different_row_counts => 0,
      different_checksums  => 0,
      sampleno             => 1,
   },
   {
      arg => "SELECT id FROM users WHERE name='bar'",
      differences          => 0,
      different_row_counts => 0,
      different_checksums  => 0,
      sampleno             => 2,
   },
   {
      arg => "SELECT id FROM users WHERE name='bar'",
      differences          => 1,
      different_row_counts => 1,
      different_checksums  => 0,
      sampleno             => 3,
   },
];

$expected = <<EOF;
# Query 1: ID 0x82860EDA9A88FCC5 at byte 0 _______________________________
# Found 1 differences in 3 samples:
#   checksums       0
#   row counts      1
#            host1 host2
# Errors         1     1
# Warnings       0     0
# Query_time            
#   sum        10s   10s
#   min         1s    1s
#   max         8s    8s
#   avg         3s    3s
#   pct_95      8s    8s
#   stddev      3s    3s
#   median   992ms 992ms
EOF

aggregate();

$result = $urf->event_report(
   meta_ea  => $meta_ea,
   hosts    => [ {name=>'host1', ea=>$ea1},
                 {name=>'host2', ea=>$ea2} ],
   where   => 'select id from users where name=?',
   rank    => 1,
   worst   => 'differences',
);

is($result, $expected, 'Event report');

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $urf->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
