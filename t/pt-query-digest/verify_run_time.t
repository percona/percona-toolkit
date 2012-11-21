#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 18;

use PerconaTest;
require "$trunk/bin/pt-query-digest";

my $m = 60;
my $h = 3600;
my $d = 86400;

sub verify {
   my ( $mode, $time ) = @_;
   my $boundary;
   eval {
      $boundary = pt_query_digest::verify_run_time(
         run_mode => $mode,
         run_time => $time,
      );
   };
   return $EVAL_ERROR if $EVAL_ERROR;
   return $boundary;
}

is(
   verify('clock', 60),
   undef,
   "clock 60s"
);

is(
   verify('event', 60),
   undef,
   "event 60s"
);

is(
   verify('interval', 60),
   $m,
   "interval 60s"
);

is(
   verify('interval', 12),
   $m,
   "interval 12s"
);

is(
   verify('interval', 2*60),
   $h,
   "interval 2m"
);

is(
   verify('interval', 60*60),
   $h,
   "interval 1h"
);

is(
   verify('interval', 60*60*3),
   $d,
   "interval 3h"
);

is(
   verify('interval', 60*60*24),
   $d,
   "interval 1d"
);

is(
   verify('interval', 60*60*24*2),
   $d*2,
   "interval 2d"
);

like(
   verify('foo', 60),
   qr/Invalid --run-time-mode/,
   "Invalid run mode"
);

like(
   verify('event', -1),
   qr/--run-time must be greater than zero/,
   "event -1s invalid"
);

is(
   verify('event', 0),
   undef,
   "event 0 invalid"
);

like(
   verify('interval', -1),
   qr/--run-time must be greater than zero/,
   "interval -1s invalid"
);

like(
   verify('interval', 0),
   qr/--run-time must be greater than zero/,
   "interval 0 invalid"
);

like(
   verify('interval', 7),
   qr/Invalid --run-time argument/,
   "interval 7s invalid"
);

like(
   verify('interval', 7*60),
   qr/Invalid --run-time argument/,
   "interval 7m invalid"
);

like(
   verify('interval', 61*60),
   qr/Invalid --run-time argument/,
   "interval 61m invalid"
);

like(
   verify('interval', 60*60*25),
   qr/Invalid --run-time argument/,
   "interval 25h invalid"
);

# #############################################################################
# Done.
# #############################################################################
exit;
