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

use ReplicaLagWaiter;
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

my $rll = new ReplicaLagWaiter(
   oktorun   => \&oktorun,
   get_lag   => \&get_lag,
   sleep     => \&sleep,
   max_lag   => 1,
   slaves    => [
      { dsn=>{n=>'slave1'}, dbh=>1 },
      { dsn=>{n=>'slave2'}, dbh=>2 },
   ],
);

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
