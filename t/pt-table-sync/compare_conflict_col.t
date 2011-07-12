#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 27;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-sync";

# Just for brevity.
sub _cmp {
   return pt_table_sync::cmp_conflict_col(@_);
}

# These constants are from mk-table-sync, defined just
# before sub cmp_conflict_col().
use constant UPDATE_LEFT      => -1;
use constant UPDATE_RIGHT     =>  1;
use constant UPDATE_NEITHER   =>  0;  # neither value equals/matches
use constant FAILED_THRESHOLD =>  2;  # failed to exceed threshold

# #############################################################################
# Sanity checks.
# #############################################################################
throws_ok(
   sub { pt_table_sync::cmp_conflict_col(1, 2, 'bad') },
   qr/Invalid comparison: bad/,
   'Dies on invalid comparison'
);

# ###########################################################################
# newest/oldest
# ###########################################################################
is(
   _cmp('2009-12-01 12:00:00', '2009-12-01 12:00:00', 'newest'),
   UPDATE_NEITHER,
   'same datetime'
);

is(
   _cmp('2009-12-01 12:00:00', '2009-12-01 12:00:011', 'newest'),
   UPDATE_LEFT,
   'newest datetime'
);

is(
   _cmp('2009-12-01 12:00:00', '2009-12-01 12:00:011', 'oldest'),
   UPDATE_RIGHT,
   'oldest datetime'
);

is(
   _cmp('2009-12-01 13:00:00', '2009-12-01 12:00:011', 'newest'),
   UPDATE_RIGHT,
   'newest datetime (reversed)'
);

is(
   _cmp('2009-12-01 13:00:00', '2009-12-01 12:00:011', 'oldest'),
   UPDATE_LEFT,
   'oldest datetime (reversed)'
);

is(
   _cmp('2009-12-01', '2009-12-02', 'newest'),
   UPDATE_LEFT,
   'newest date'
);

is(
   _cmp('2009-12-01', '2009-12-02', 'oldest'),
   UPDATE_RIGHT,
   'oldest date'
);

is(
   _cmp('12:00:00', '12:00:011', 'newest'),
   UPDATE_LEFT,
   'newest time'
);

is(
   _cmp('12:00:00', '12:00:011', 'oldest'),
   UPDATE_RIGHT,
   'oldest time'
);

is(
   _cmp('2009-12-01 12:00:00', '2009-12-01 12:05:00', 'newest', undef,
      '5m'),
   UPDATE_LEFT,
   'newest datetime, threshold ok'
);

is(
   _cmp('2009-12-01 12:00:00', '2009-12-01 12:05:00', 'newest', undef,
      '6m'),
   FAILED_THRESHOLD,
   'newest datetime, failed threshold'
);

is(
   _cmp('2009-12-01 12:00:00', '2009-12-01 12:05:00', 'oldest', undef,
      '5m'),
   UPDATE_RIGHT,
   'oldest datetime, threshold ok'
);

is(
   _cmp('2009-12-01 12:00:00', '2009-12-01 12:05:00', 'oldest', undef,
      '6m'),
   FAILED_THRESHOLD,
   'oldest datetime, failed threshold'
);

is(
   _cmp('2009-12-01', '2009-12-03', 'newest', undef,
      '2d'),
   UPDATE_LEFT,
   'newest date, threshold ok'
);

is(
   _cmp('2009-12-01', '2009-12-03', 'newest', undef,
      '3d'),
   FAILED_THRESHOLD,
   'newest date, failed threshold'
);

# ###########################################################################
# greatest/least
# ###########################################################################
is(
   _cmp(11, 11, 'greatest'),
   UPDATE_NEITHER,
   'same number'
);

is(
   _cmp(11, 10, 'greatest'),
   UPDATE_RIGHT,
   'greatest'
);

is(
   _cmp(11, 10, 'least'),
   UPDATE_LEFT,
   'least'
);

is(
   _cmp(20, 10, 'least', undef, 10),
   UPDATE_LEFT,
   'least, threshold ok'
);

is(
   _cmp(20, 10, 'least', undef, 11),
   FAILED_THRESHOLD,
   'least, failed threshold'
);

# #############################################################################
# equals
# #############################################################################
is(
   _cmp('foo', 'bar', 'equals', 'foo'),
   UPDATE_RIGHT,
   'equals left, update right'
);

is(
   _cmp('foo', 'bar', 'equals', 'bar'),
   UPDATE_LEFT,
   'equals right, update left'
);

is(
   _cmp('foo', 'bar', 'equals', 'banana'),
   UPDATE_NEITHER,
   'equals neither'
);

# #############################################################################
# matches
# #############################################################################
is(
   _cmp('foo', 'bar', 'matches', '^f..'),
   UPDATE_RIGHT,
   'matches left, update right'
);

is(
   _cmp('foo', 'bar', 'matches', '.[ar]+$'),
   UPDATE_LEFT,
   'matches right, update left'
);

is(
   _cmp('foo', 'bar', 'matches', '^foo.$'),
   UPDATE_NEITHER,
   'matches neither'
);

# #############################################################################
# Done.
# #############################################################################
exit;
