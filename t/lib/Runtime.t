#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 20;

use PerconaTest;
use Runtime;

# #############################################################################
# Test a runtime obj with clock time.
# #############################################################################

my $runtime = new Runtime(
   now     => sub { return time; },
   run_time => 3,
);

is(
   $runtime->time_elapsed(),
   0,
   "No time has elapsed yet"
);

is(
   $runtime->time_left(),
   3,
   "First call to time_left() starts the countdown"
);

sleep 1;
my $t = $runtime->time_left();
ok(
   $t < 3 && $t > 0,
   "Time is running out"
);

ok(
   $runtime->have_time(),
   "Have time"
);

is(
   $runtime->time_elapsed(),
   1,
   "Reports 1s elapsed"
);
   
sleep 2;
$t = $runtime->time_left();
is(
   $t,
   0,
   "Zero time left"
);

ok(
   !$runtime->have_time(),
   "Don't have time"
);

sleep 1;
$t = $runtime->time_left();
ok(
   $t < 0,
   "Runtime has elapsed"
);

ok(
   !$runtime->have_time(),
   "Still don't have time"
);

$runtime->reset();
is(
   $runtime->time_left(),
   3,
   "Reset countdown"
);

# #############################################################################
# Test a runtime obj with clock time running forever.
# #############################################################################

$runtime = new Runtime(
   now     => sub { return time; },
   # run_time => undef,  # forever
);

is(
   $runtime->time_left(),
   undef,
   "Running forever: time_left() is undefined"
);

sleep 2;

is(
   $runtime->time_left(),
   undef,
   "Running forever: time_left() is still undefined"
);

ok(
   $runtime->have_time(),
   "Running forever: Have time"
);

is(
   $runtime->time_elapsed(),
   2,
   "Running forever: time still elapses"
);

# #############################################################################
# Test start/stop with clock time.
# #############################################################################

$runtime = new Runtime(
   now     => sub { return time; },
   run_time => 3,
);

is(
   $runtime->time_left(),
   3,
   "Start/stop: started with 3s left"
);

$runtime->stop();

is(
   $runtime->have_time(),
   0,
   "Start/stop: no time after stop"
);

# #############################################################################
# Test a runtime obj with fake time.
# #############################################################################

my @time = qw(0 3 7 9);
$runtime = new Runtime(
   now     => sub { return shift @time; },
   run_time => 8,
);

is(
   $runtime->time_left(),
   8,
   "Fake time: first call to time_left()"
);

is(
   $runtime->time_left(),
   5,
   "Fake time: second call to time_left() as if 3s passed"
);

is(
   $runtime->time_left(),
   1,
   "Fake time: as if 4s more passed"
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $runtime->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
