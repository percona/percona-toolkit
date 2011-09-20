#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 17;

use ReplicaLagLimiter;
use PerconaTest;

my $rll = new ReplicaLagLimiter(
   spec        => [qw(max=1 timeout=3600 continue=no)],
   slaves      => [
      { dsn=>{n=>'slave1'}, dbh=>1 },
      { dsn=>{n=>'slave2'}, dbh=>2 },
   ],
   get_lag     => \&get_lag,
   initial_n   => 1000,
   initial_t   => 1,
   target_t    => 1,
);

# ############################################################################
# Validate spec.
# ############################################################################
is(
   ReplicaLagLimiter::validate_spec(['max=1','timeout=3600','continue=no']),
   1,
   "Valid spec"
);

throws_ok(
   sub {
      ReplicaLagLimiter::validate_spec(['max=1','timeout=3600','foo,bar'])
   },
   qr/invalid spec format, should be option=value: foo,bar/,
   "Invalid spec format"
);

throws_ok(
   sub {
      ReplicaLagLimiter::validate_spec(['max=1','timeout=3600','foo=bar'])
   },
   qr/unknown option in spec: foo=bar/,
   "Unknown spec option"
);

throws_ok(
   sub {
      ReplicaLagLimiter::validate_spec(['max=1','timeout=yes'])
   },
   qr/value must be an integer: timeout=yes/,
   "Value must be int"
);

throws_ok(
   sub {
      ReplicaLagLimiter::validate_spec(['max=1','continue=1'])
   },
   qr/value for continue must be "yes" or "no"/,
   "Value must be yes or no"
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
my @waited = ();
my @lag    = ();
sub get_lag {
   my ($dbh) = @_;
   push @waited, $dbh;
   my $lag = shift @lag || 0;
   return $lag;
}

@lag = (0, 0);
is(
   $rll->wait(),
   1,
   "wait() returns 1 if all slaves catch up"
);

is_deeply(
   \@waited,
   [1,2],
   "Waited for all slaves"
);

@waited = ();
@lag    = (5, 0, 0);
my $t   = time;
my $ret = $rll->wait(),
ok(
   time - $t >= 0.9,
   "wait() waited a second"
);

is_deeply(
   \@waited,
   [1, 1, 2],
   "wait() waited for first slave"
);

# Lower timeout to check if wait() will die.
$rll = new ReplicaLagLimiter(
   spec        => [qw(max=1 timeout=0.75 continue=no)],
   slaves      => [
      { dsn=>{n=>'slave1'}, dbh=>1 },
      { dsn=>{n=>'slave2'}, dbh=>2 },
   ],
   get_lag     => \&get_lag,
   initial_n   => 1000,
   initial_t   => 1,
   target_t    => 1,
);

@waited = ();
@lag    = (5, 0, 0);
throws_ok(
   sub { $rll->wait() },
   qr/Timeout waiting for replica slave1 to catch up/,
   "wait() dies on timeout"
);

# Continue despite not catching up.
$rll = new ReplicaLagLimiter(
   spec        => [qw(max=1 timeout=0.75 continue=yes)],
   slaves      => [
      { dsn=>{n=>'slave1'}, dbh=>1 },
      { dsn=>{n=>'slave2'}, dbh=>2 },
   ],
   get_lag     => \&get_lag,
   initial_n   => 1000,
   initial_t   => 1,
   target_t    => 1,
);

@waited = ();
@lag    = (5, 0, 0);
is(
   $rll->wait(),
   0,
   "wait() returns 0 if timeout and continue=yes"
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
