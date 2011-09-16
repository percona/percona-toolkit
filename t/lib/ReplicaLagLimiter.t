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

use ReplicaLagLimiter;
use PerconaTest;


my $lag = 0;
sub get_lag {
   my ($dbh) = @_;
   return $lag;
}

my $sll = new ReplicaLagLimiter(
   spec    => [qw(max=1 timeout=3600 continue=no)],
   slaves  => [[]],
   get_lag => \&get_lag,
);

for (1..4) {
   $sll->update(1);
}
is(
   $sll->update(1),
   0,
   "5 time samples, no adjustmenet"
);

for (1..4) {
   $sll->update(1);
}
is(
   $sll->update(1),
   0,
   "Moving avg hasn't changed"
);

$sll->update(2);
$sll->update(2);
$sll->update(2);
is(
   $sll->update(2),
   -1,
   "Adjust down (moving avg = 1.8)"
);

$sll->update(0.3);
$sll->update(0.3);
is(
   $sll->update(0.3),
   1,
   "Adjust up (moving avg = 0.98)"
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $sll->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
