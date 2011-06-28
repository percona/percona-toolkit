# This program is copyright 2011 Percona Inc.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.
# ###########################################################################
# Runtime package $Revision: 7221 $
# ###########################################################################

# Package: Runtime
# Runtime keeps track of time to control how long a tool's main loop runs.
# This package was created to handle mk-query-digest --run-time-mode event.
# In essence, we abstract time so that the tool doesn't know/care whether
# now() comes from a clock, a log timestamp, or wherever.  The creator of
# Runtime object determines how, or from where, time is gotten so that the
# caller of the object can simply ask, "What time is it?".
{
package Runtime;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   now     - Callback that sets current time.
#   runtime - Amount of time to run in seconds, or undef for forever.
#
# Returns:
#   Runtime object
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(now);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   if ( ($args{runtime} || 0) < 0 ) {
      die "runtime argument must be greater than zero"
   }

   my $self = {
      %args,
      start_time => undef,
      end_time   => undef,
      time_left  => undef,
      stop       => 0,
   };

   return bless $self, $class;
}

# Sub: time_left
#   Return the number of runtime seconds left or undef for forever.
#   The return may be less than zero if the runtime has been exceeded.
#   The first call to this subroutine "starts the clock", so to speak,
#   if the now callbackup returns a defined value.
#
# Parameters:
#   %args - Arguments passed to now callback.
#
# Returns:
#   Number of runtime seconds left, possibly less than zero, or undef
#   if running forever.
sub time_left {
   my ( $self, %args ) = @_;

   if ( $self->{stop} ) {
      MKDEBUG && _d("No time left because stop was called");
      return 0;
   }

   my $now = $self->{now}->(%args);
   MKDEBUG && _d("Current time:", $now);

   # Don't !$var check stuff because since time may not be from a clock,
   # a time of 0 might be used and be valid.
   if ( !defined $self->{start_time} ) {
      $self->{start_time} = $now;
   }

   # An undefined now time might be returned if the now callback isn't
   # ready or willing to start yet.  We can't determine time left until
   # we know the current time.
   return unless defined $now;

   # If runtime is also defined, then we can determine time left.
   # If it's not defined, then we're running forever.
   my $runtime = $self->{runtime};
   return unless defined $runtime;

   # Set the end time once.
   if ( !$self->{end_time} ) {
      $self->{end_time} = $now + $runtime;
      MKDEBUG && _d("End time:", $self->{end_time});
   }

   # Calculate and return the amount of time left in seconds.
   # This may be negative.  Use have_time() for a bool return.
   $self->{time_left} = $self->{end_time} - $now;
   MKDEBUG && _d("Time left:", $self->{time_left});
   return $self->{time_left};
}

# Sub: have_time
#   Return true or false if there's runtime left.  This sub is a simpler
#   wrapper around <time_left()> which returns true (1) if time left is
#   defined and greater than zero or undef, else returns false.
#
# Parameters:
#   %args - Arguments passed to now callback.
#
# Returns:
#   True if time left is defined and greater than zero or undef, else false.
sub have_time {
   my ( $self, %args ) = @_;
   my $time_left = $self->time_left(%args);
   return 1 if !defined $time_left;  # run forever
   return $time_left <= 0 ? 0 : 1;   # <=0s means runtime has elapsed
}

# Sub: time_elapsed
#   How much time has elapsed since <time_left()> was first called.
#
# Parameters:
#   %args - Arguments passed to now callback.
#
# Returns:
#   Number of seconds elapsed since <time_left()> was first called.
sub time_elapsed {
   my ( $self, %args ) = @_;

   # Either time_left() hasn't been called yet or it has but the now
   # callback hasn't returned a defined time.  If we haven't started
   # then no time has elapsed.
   my $start_time = $self->{start_time};
   return 0 unless $start_time;

   my $now = $self->{now}->(%args);
   MKDEBUG && _d("Current time:", $now);

   my $time_elapsed = $now - $start_time;
   MKDEBUG && _d("Time elapsed:", $time_elapsed);
   if ( $time_elapsed < 0 ) {
      warn "Current time $now is earlier than start time $start_time";
   }
   return $time_elapsed;
}

# Sub: reset
#   Reset this Runtime object for another run.  If you want to re-use this
#   object (e.g. for another iteration of the tool's main loop), call this
#   sub to reset the internally saved times for <time_left()> and
#   <have_time()>.
sub reset {
   my ( $self ) = @_;
   $self->{start_time} = undef;
   $self->{end_time}   = undef;
   $self->{time_left}  = undef;
   $self->{stop}       = 0;
   MKDEBUG && _d("Reset runtime");
   return;
}

# Sub: stop
#   Stop the coutdown, make <time_left()> return 0 and <have_time()> false.
#   After calling this sub, you must call <start()> or <reset()> to
#   recommence the countdown.
sub stop {
   my ( $self ) = @_;
   $self->{stop} = 1;
   return;
}

# Sub: start
#   Restart the countdown after having called <stop()>.  Calling this sub
#   has no affect unless <stop()> was called first.
sub start {
   my ( $self ) = @_;
   $self->{stop} = 0;
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End Runtime package
# ###########################################################################
