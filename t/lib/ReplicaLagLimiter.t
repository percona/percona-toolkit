#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 16;

use ReplicaLagLimiter;
use PerconaTest;

my $rll = new ReplicaLagLimiter(
   spec        => [qw(max=1 timeout=3600 continue=no)],
   slaves      => [
      { dsn=>{n=>'slave1'}, dbh=>1 },
      { dsn=>{n=>'slave2'}, dbh=>2 },
   ],
   get_lag     => \&get_lag,
   target_time => 1,
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
for (1..4) {
   $rll->update(1000, 1);
}
is(
   $rll->update(1000, 1),
   0,
   "5 time samples, no adjustmenet"
);

for (1..4) {
   $rll->update(1000, 1);
}
is(
   $rll->update(1000, 1),
   0,
   "Avg hasn't changed"
);

# Results in: Weighted avg n: 1000 s: 1.683593 rate: 593 n/s
$rll->update(1000, 2);
$rll->update(1000, 2);
$rll->update(1000, 2);
is(
   $rll->update(1000, 2),
   -1,
   "Adjust down"
);

# Results in: Weighted avg n: 1000 s: 0.768078 rate: 1301 n/s
$rll->update(1000, 0.1);
$rll->update(1000, 0.1);
is(
   $rll->update(1000, 0.1),
   1,
   "Adjust up"
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
   target_time => [0.9,1.1],
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
   target_time => [0.9,1.1],
);

@waited = ();
@lag    = (5, 0, 0);
is(
   $rll->wait(),
   1,
   "wait() returns 1 despite timeout if continue=yes"
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
