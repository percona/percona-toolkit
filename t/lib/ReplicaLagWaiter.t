#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 7;

use ReplicaLagWaiter;
use Cxn;
use PerconaTest;

my $oktorun = 1;
my @waited  = ();
my @lag     = ();
my @sleep   = ();
my @worst   = ();

sub oktorun {
   return $oktorun;
}

sub get_lag {
   my ($cxn) = @_;
   push @waited, $cxn->dbh();
   my $lag = shift @lag || 0;
   return $lag;
}

sub sleep {
   push @worst, [@_];
   my $t = shift @sleep || 0;
   sleep $t;
}

my $r1 = new Cxn(dsn=>{n=>'slave1'}, dbh=>1, DSNParser=>1, OptionParser=>1);
my $r2 = new Cxn(dsn=>{n=>'slave2'}, dbh=>2, DSNParser=>1, OptionParser=>1);

my $rll = new ReplicaLagWaiter(
   oktorun => \&oktorun,
   get_lag => \&get_lag,
   sleep   => \&sleep,
   max_lag => 1,
   slaves  => [$r1, $r2],
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

is_deeply(
   \@worst,
   [],
   "Did not call sleep callback"
);

@waited = ();
@lag    = (3, 5, 0, 0);
@sleep  = (1, 1, 1, 1);
@worst  = ();
$t   = time;
$rll->wait(),
ok(
   time - $t >= 0.9,
   "wait() waited a second"
);

is_deeply(
   \@waited,
   [1, 2, 2, 1],
   "wait() waited for first slave"
);

# This tests that the code sorts the lag correctly.  r2 is lagging
# the worst (5 > 3) so it should be passed to the sleep callback.
is_deeply(
   \@worst,
   [
      [ $r2, 5 ],
   ],
   "Called sleep callback with worst lagger"
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
