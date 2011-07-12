#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 5;

use TCPRequestAggregator;
use PerconaTest;

my $in = "t/lib/samples/simple-tcprequests/";
my $p;

# Check that I can parse a simple log and aggregate it into 100ths of a second
$p = new TCPRequestAggregator(interval => '.01', quantile => '.99');
# intervals.
test_log_parser(
   parser => $p,
   file   => "$in/simpletcp-requests001.txt",
   result => [
      {  ts            => '1301957863.82',
         concurrency   => '0.346932',
         throughput    => '1800.173395',
         arrivals      => 18,
         completions   => 17,
         weighted_time => '0.003469',
         sum_time      => '0.003492',
         variance_mean => '0.000022',
         quantile_time => '0.000321',
         obs_time      => '0.009999',
         busy_time     => '0.002861',
         pos_in_log    => 0,
      },
      {  ts            => '1301957863.83',
         concurrency   => '0.649048',
         throughput    => '1600.001526',
         arrivals      => 16,
         completions   => 16,
         weighted_time => '0.006490',
         sum_time      => '0.011227',
         variance_mean => '0.004070',
         quantile_time => '0.007201',
         obs_time      => '0.010000',
         busy_time     => '0.004933',
         pos_in_log    => 1296,
      },
      {  ts            => '1301957863.84',
         concurrency   => '1.000000',
         throughput    => '0.000000',
         arrivals      => 0,
         completions   => 1,
         weighted_time => '0.004759',
         sum_time      => '0.000000',
         variance_mean => '0.000000',
         quantile_time => '0.000000',
         obs_time      => '0.004759',
         busy_time     => '0.004759',
         pos_in_log    => '2448',
      },
   ],
);

# Check that I can parse a log whose first event is ID = 0, and whose events all
# fit within one time interval.
$p = new TCPRequestAggregator(interval => '.01', quantile => '.99');
test_log_parser(
   parser => $p,
   file   => "$in/simpletcp-requests002.txt",
   result => [
      {  ts            => '1301957863.82',
         concurrency   => '0.353948',
         throughput    => '1789.648311',
         arrivals      => 17,
         completions   => 17,
         weighted_time => '0.003362',
         variance_mean => '0.000022',
         sum_time      => '0.003362',
         quantile_time => '0.000321',
         obs_time      => '0.009499',
         busy_time     => '0.002754',
         pos_in_log    => 0,
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
