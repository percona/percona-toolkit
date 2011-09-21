#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 10;

use ReplicaLagLimiter;
use PerconaTest;

my $oktorun = 1;
my @waited  = ();
my @lag     = ();
my @sleep   = ();

sub oktorun {
   return $oktorun;
}

sub get_lag {
   my ($dbh) = @_;
   push @waited, $dbh;
   my $lag = shift @lag || 0;
   return $lag;
}

sub sleep {
   my $t = shift @sleep || 0;
   sleep $t;
}

my $rll = new ReplicaLagLimiter(
   oktorun   => \&oktorun,
   get_lag   => \&get_lag,
   sleep     => \&sleep,
   max_lag   => 1,
   initial_n => 1000,
   initial_t => 1,
   target_t  => 1,
   slaves    => [
      { dsn=>{n=>'slave1'}, dbh=>1 },
      { dsn=>{n=>'slave2'}, dbh=>2 },
   ],
);

# ############################################################################
# Update master op, see if we get correct adjustment result.
# ############################################################################

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
   542,
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

# ############################################################################
# Fake waiting for slaves.
# ############################################################################
@lag = (0, 0);
my $t = time;
$rll->wait();
ok(
   time - $t < 0.5,
   "wait() returns immediately if all slaves are ready"
);

is_deeply(
   \@waited,
   [1,2],
   "Waited for all slaves"
);

@waited = ();
@lag    = (5, 0, 0);
@sleep  = (1, 1, 1);
$t   = time;
$rll->wait(),
ok(
   time - $t >= 0.9,
   "wait() waited a second"
);

is_deeply(
   \@waited,
   [1, 2, 1],
   "wait() waited for first slave"
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
