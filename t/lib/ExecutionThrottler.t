#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 12;

use ExecutionThrottler;
use PerconaTest;

use constant PTDEBUG => $ENV{PTDEBUG};

my $rate    = 100;
my $oktorun = 1;
my $time    = 1.000001;
my $stats   = {};
my %args = (
   event   => { arg => 'query', },
   oktorun => sub { return $oktorun; },
   misc    => { time => $time },
   stats   => $stats,
);
my $get_rate = sub { return $rate; };

my $et = new ExecutionThrottler(
   rate_max  => 90,
   get_rate  => $get_rate,
   check_int => 0.4,
   step      => 0.8,
);

isa_ok($et, 'ExecutionThrottler');

# This event won't be checked because 0.4 seconds haven't passed
# so Skip_exec should still be 0 even though the rate is past max.
is_deeply(
   $et->throttle(%args),
   $args{event},
   'Event before first check'
);

# Since the event above wasn't checked, the skip prop should still be zero.
is(
   $et->skip_probability,
   0.0,
   'Zero skip prob'
);

# Let a time interval pass, 0.4s.
$args{misc}->{time} += 0.4;

# This event will be checked because a time interval has passed.
# The avg int rate will be 100, so skip prop should be stepped up
# by 0.8 and Skip_exec will have an 80% chance of being set true.
my $event = $et->throttle(%args);
ok(
   exists $event->{Skip_exec},
   'Event after check, exceeds rate max, got Skip_exec attrib'
);

is(
   $et->skip_probability,
   0.8,
   'Skip prob stepped by 0.8'
);

# Inject another rate sample and then sleep until the next check.
$rate = 50;
$et->throttle(%args);
$args{misc}->{time} += 0.45;

# This event should be ok because the avg rate dropped below max.
# skip prob should be stepped down by 0.8, to zero.
is_deeply(
   $et->throttle(%args),
   $args{event},
   'Event ok at min rate'
);

is(
   $et->skip_probability,
   0,
   'Skip prob stepped down'
);

# Increase the rate to max and check that it's still ok.
$rate = 90;
$et->throttle(%args);
$args{misc}->{time} += 0.45;

is_deeply(
   $et->throttle(%args),
   $args{event},
   'Event ok at max rate'
);

# The avg int rates were 100, 50, 90 = avg 80.
is(
   $et->rate_avg,
   80,
   'Calcs average rate'
);

is(
   $stats->{throttle_rate_min},
   50,
   'Stats min rate'
);

is(
   $stats->{throttle_rate_max},
   100,
   'Stats max rate'
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $et->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
