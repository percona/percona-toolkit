#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 6;

use WeightedAvgRate;
use PerconaTest;

my $rll = new WeightedAvgRate(
   initial_n => 1000,
   initial_t => 1,
   target_t  => 1,
);

# stay the same
for (1..5) {
   $rll->update(1000, 1);
}
is(
   $rll->update(1000, 1),
   1000,
   "Same rate, same n"
);

# slow down
for (1..5) {
   $rll->update(1000, 2);
}
is(
   $rll->update(1000, 2),
   540,
   "Decrease rate, decrease n"
);

for (1..15) {
   $rll->update(1000, 2);
}
is(
   $rll->update(1000, 2),
   500,
   "limit n=500 decreasing"
);

# speed up
for (1..5) {
   $rll->update(1000, 1);
}
is(
   $rll->update(1000, 1),
   849,
   "Increase rate, increase n"
);

for (1..20) {
   $rll->update(1000, 1);
}
is(
   $rll->update(1000, 1),
   999,
   "limit n=1000 increasing"
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $rll->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
