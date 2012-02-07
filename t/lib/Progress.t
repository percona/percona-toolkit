#!/usr/bin/perl

BEGIN {
   die
      "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
}

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 31;

use Transformers;
use Progress;
use PerconaTest;

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $pr;
my $how_much_done    = 0;
my $callbacks_called = 0;
my $completion_arr   = [];

# #############################################################################
# Checks that the command-line interface works OK
# #############################################################################

foreach my $test ( (
      [  sub { Progress->validate_spec([qw()]) },
         'spec array requires a two-part argument', ],
      [  sub { Progress->validate_spec([qw(foo bar)]) },
         'spec array\'s first element must be one of percentage,time,iterations', ],
      [  sub { Progress::validate_spec([qw(time bar)]) },
         'spec array\'s second element must be an integer', ],
   )
) {
   throws_ok($test->[0], qr/$test->[1]/, $test->[1]);
}

$pr = new Progress (
   jobsize => 100,
   spec    => [qw(percentage 15)],
);
is ($pr->{jobsize}, 100, 'jobsize is 100');
is ($pr->{report}, 'percentage', 'report is percentage');
is ($pr->{interval}, 15, 'interval is 15');

# #############################################################################
# Simple percentage-based completion.
# #############################################################################

$pr = new Progress(
   jobsize  => 100,
   report   => 'percentage',
   interval => 5,
);

is($pr->fraction_modulo(.01), 0, 'fraction_modulo .01');
is($pr->fraction_modulo(.04), 0, 'fraction_modulo .04');
is($pr->fraction_modulo(.05), 5, 'fraction_modulo .05');
is($pr->fraction_modulo(.09), 5, 'fraction_modulo .09');

$pr->set_callback(
   sub{
      my ( $fraction, $elapsed, $remaining, $eta ) = @_;
      $how_much_done = $fraction * 100;
      $callbacks_called++;
   }
);

# 0 through 4% shouldn't trigger the callback to be called, so $how_much_done
# should stay at 0%.
my $i = 0;
for (0..4) {
   $pr->update(sub{return $i});
   $i++;
}
is($how_much_done, 0, 'Progress has not been updated yet');
is($callbacks_called, 0, 'Callback has not been called');

# Now we cross the 5% threshold... this should call the callback.
$pr->update(sub{return $i});
$i++;
is($how_much_done, 5, 'Progress updated to 5%');
is($callbacks_called, 1, 'Callback has been called');

for (6..99) {
   $pr->update(sub{return $i});
   $i++;
}
is($how_much_done, 95, 'Progress updated to 95%'); # Not 99 because interval=5
is($callbacks_called, 19, 'Callback has been called 19 times');

# Go to 100%
$pr->update(sub{return $i});
is($how_much_done, 100, 'Progress updated to 100%');
is($callbacks_called, 20, 'Callback has been called 20 times');

# Can't go beyond 100%, right?
$pr->update(sub{return 200});
is($how_much_done, 100, 'Progress stops at 100%');
is($callbacks_called, 20, 'Callback not called any more times');

# #############################################################################
# Iteration-based completion.
# #############################################################################

$pr = new Progress(
   jobsize  => 500,
   report   => 'iterations',
   interval => 2,
);
$how_much_done    = 0;
$callbacks_called = 0;
$pr->set_callback(
   sub{
      my ( $fraction, $elapsed, $remaining, $eta ) = @_;
      $how_much_done = $fraction * 100;
      $callbacks_called++;
   }
);

$i = 0;
for ( 0 .. 50 ) {
   $pr->update(sub{return $i});
   $i++;
}
is($how_much_done, 10, 'Progress is 10% done');
is($callbacks_called, 26, 'Callback called every 2 iterations');

# #############################################################################
# Time-based completion.
# #############################################################################

$pr = new Progress(
   jobsize  => 600,
   report   => 'time',
   interval => 10, # Every ten seconds
);
$pr->start(10); # Current time is 10 seconds.
$completion_arr = [];
$callbacks_called  = 0;
$pr->set_callback(
   sub{
      $completion_arr = [ @_ ];
      $callbacks_called++;
   }
);
$pr->update(sub{return 60}, now => 35);
is_deeply(
   $completion_arr,
   [.1, 25, 225, 260, 60 ],
   'Got completion info for time-based stuff'
);
is($callbacks_called, 1, 'Callback called once');

# #############################################################################
# Test the default callback
# #############################################################################

my $buffer;
eval {
   local *STDERR;
   open STDERR, '>', \$buffer or die $OS_ERROR;
   $pr = new Progress(
      jobsize  => 600,
      report   => 'time',
      interval => 10, # Every ten seconds
   );
   $pr->start(10); # Current time is 10 seconds.
   $pr->update(sub{return 60}, now => 35);
   is($buffer, "Progress:  10% 03:45 remain\n",
      'Tested the default callback');
};
is ($EVAL_ERROR, '', "No error in default callback");

$buffer = '';
eval {
   local *STDERR;
   open STDERR, '>', \$buffer or die $OS_ERROR;
   $pr = new Progress(
      jobsize  => 600,
      report   => 'time',
      interval => 10, # Every ten seconds
      name     => 'custom name',
      start    => 10, # Current time is 10 seconds, alternate interface
   );
   is($pr->{start}, 10, 'Custom start time param works');
   $pr->update(sub{return 60}, now => 35);
   is($buffer, "custom name:  10% 03:45 remain\n",
      'Tested the default callback with custom name');
};
is ($EVAL_ERROR, '', "No error in default callback with custom name");

# ############################################################################
# Do a "first report" before the normal interval reports.
# ############################################################################
$pr = new Progress(
   jobsize  => 600,
   report   => 'time',
   interval => 10, # Every ten seconds
);
$pr->start(2); # Current time is 2 seconds.
$callbacks_called       = 0;
my $first_report_called = 0;
$pr->set_callback(
   sub {
      $completion_arr = [ @_ ];
      $callbacks_called++;
   }
);
$pr->update(
   sub { return 60 },
   now          => 5,
   first_report =>  sub { $first_report_called++ }
);
$pr->update(
   sub { return 70 },
   now          => 16,
   first_report =>  sub { $first_report_called++ }
);
$pr->update(
   sub { return 100 },
   now          => 27,
   first_report =>  sub { $first_report_called++ }
);

is(
   $first_report_called,
   1,
   "Called first_report ocne"
);

is(
   $callbacks_called,
   2,
   "Called interval report twice"
);

# #############################################################################
# Done.
# #############################################################################
exit;
