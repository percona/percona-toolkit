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
use Data::Dumper;

use PerconaTest;
use Sandbox;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

require "$trunk/bin/pt-upgrade";

sub test_diff_query_times {
   my (%args) = @_;

   my $diff = pt_upgrade::diff_query_times(
      query_time1 => $args{t1},
      query_time2 => $args{t2},
   );
   is_deeply(
      $diff,
      $args{expect},
      "$args{t1} vs. $args{t2}"
   ) or diag(Dumper($diff));
}

test_diff_query_times(
   t1     => 0,
   t2     => 0,
   expect => undef,
);

test_diff_query_times(
   t1     => 1,
   t2     => 1,
   expect => undef,
);

test_diff_query_times(
   t1     => 0.01,
   t2     => 0.5,
   expect => ['0.01', '0.5', '50.0'],
);

test_diff_query_times(
   t1     => 23,
   t2     => 82,
   expect => undef,
);

test_diff_query_times(
   t1     => 23,
   t2     => 820,
   expect => [ 23, 820, 35.7 ],
);

# Just .01 shy of 1 order of mag. diff.
test_diff_query_times(
   t1     => 0.09,
   t2     => 0.89,
   expect => undef,
);

# Exactly 1 order of mag. diff.
test_diff_query_times(
   t1     => 0.09,
   t2     => 0.9,
   expect => [ 0.09, 0.9, '10.0' ],
);

# An order of mag. decrease, which is ok.
test_diff_query_times(
   t1     => 0.9,
   t2     => 0.09,
   expect => undef,
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
