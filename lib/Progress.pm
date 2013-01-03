# This program is copyright 2010-2011 Percona Ireland Ltd.
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
# Progress package
# ###########################################################################
{
# Package: Progress
# Progress encapsulates a progress report.
package Progress;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# This module encapsulates a progress report.  To create a new object, pass in
# the following:
#  jobsize  Must be a number; defines the job's completion condition
#  report   How and when to report progress.  Possible values:
#              percentage: based on the percentage complete.
#              time:       based on how much time elapsed.
#              iterations: based on how many progress updates have happened.
#  interval How many of whatever's specified in 'report' to wait before
#           reporting progress: report each X%, each X seconds, or each X
#           iterations.
#
# The 'report' and 'interval' can also be omitted, as long the following option
# is passed:
#  spec     An arrayref of [report,interval].  This is convenient to use from a
#           --progress command-line option that is an array.
#
# Optional arguments:
#  start    The start time of the job; can also be set by calling start()
#  fraction How complete the job is, as a number between 0 and 1.  Updated by
#           calling update().  Normally don't specify this.
#  name     If you want to use the default progress indicator, by default it
#           just prints out "Progress: ..." but you can replace "Progress" with
#           whatever you specify here.
sub new {
   my ( $class, %args ) = @_;
   foreach my $arg (qw(jobsize)) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   if ( (!$args{report} || !$args{interval}) ) {
      if ( $args{spec} && @{$args{spec}} == 2 ) {
         @args{qw(report interval)} = @{$args{spec}};
      }
      else {
         die "I need either report and interval arguments, or a spec";
      }
   }

   my $name  = $args{name} || "Progress";
   $args{start} ||= time();
   my $self;
   $self = {
      last_reported => $args{start},
      fraction      => 0,       # How complete the job is
      callback      => sub {
         my ($fraction, $elapsed, $remaining, $eta) = @_;
         printf STDERR "$name: %3d%% %s remain\n",
            $fraction * 100,
            Transformers::secs_to_time($remaining),
            Transformers::ts($eta);
      },
      %args,
   };
   return bless $self, $class;
}

# Validates the 'spec' argument passed in from --progress command-line option.
# It calls die with a trailing newline to avoid auto-adding the file/line.
sub validate_spec {
   shift @_ if $_[0] eq 'Progress'; # Permit calling as Progress-> or Progress::
   my ( $spec ) = @_;
   if ( @$spec != 2 ) {
      die "spec array requires a two-part argument\n";
   }
   if ( $spec->[0] !~ m/^(?:percentage|time|iterations)$/ ) {
      die "spec array's first element must be one of "
        . "percentage,time,iterations\n";
   }
   if ( $spec->[1] !~ m/^\d+$/ ) {
      die "spec array's second element must be an integer\n";
   }
}

# Specify your own custom way to report the progress.  The default is to print
# the percentage to STDERR.  This is created in the call to new().  The
# callback is a subroutine that will receive the fraction complete from 0 to
# 1, seconds elapsed, seconds remaining, and the Unix timestamp of when we
# expect to be complete.
sub set_callback {
   my ( $self, $callback ) = @_;
   $self->{callback} = $callback;
}

# Set the start timer of when work began.  You can either set it to time() which
# is the default, or pass in a value.
sub start {
   my ( $self, $start ) = @_;
   $self->{start} = $self->{last_reported} = $start || time();
   $self->{first_report} = 0;
}

# Provide a progress update.  Pass in a callback subroutine which this code can
# use to ask how complete the job is.  This callback will be called as
# appropriate.  For example, in time-lapse updating, it won't be called unless
# it's time to report the progress.  The callback has to return a number that's
# of the same dimensions as the jobsize.  For example, if a text file has 800
# lines to process, that's a jobsize of 800; the callback should return how
# many lines we're done processing -- a number between 0 and 800.  You can also
# optionally pass in the current time, but this is only for testing.
sub update {
   my ( $self, $callback, %args ) = @_;
   my $jobsize   = $self->{jobsize};
   my $now    ||= $args{now} || time;

   $self->{iterations}++; # How many updates have happened;

   # The caller may want to report something special before the actual
   # first report ($callback) if, for example, they know that the wait
   # could be long.  This is called only once; subsequent reports will
   # come from $callback after 30s, or whatever the interval is.
   if ( !$self->{first_report} && $args{first_report} ) {
      $args{first_report}->();
      $self->{first_report} = 1;
   }

   # Determine whether to just quit and return...
   if ( $self->{report} eq 'time'
         && $self->{interval} > $now - $self->{last_reported}
   ) {
      return;
   }
   elsif ( $self->{report} eq 'iterations'
         && ($self->{iterations} - 1) % $self->{interval} > 0
   ) {
      return;
   }
   $self->{last_reported} = $now;

   # Get the updated status of the job
   my $completed = $callback->();
   $self->{updates}++; # How many times we have run the update callback

   # Sanity check: can't go beyond 100%
   return if $completed > $jobsize;

   # Compute the fraction complete, between 0 and 1.
   my $fraction = $completed > 0 ? $completed / $jobsize : 0;

   # Now that we know the fraction completed, we can decide whether to continue
   # on and report, for percentage-based reporting.  Have we crossed an
   # interval-percent boundary since the last update?
   if ( $self->{report} eq 'percentage'
         && $self->fraction_modulo($self->{fraction})
            >= $self->fraction_modulo($fraction)
   ) {
      # We're done; we haven't advanced progress enough to report.
      $self->{fraction} = $fraction;
      return;
   }
   $self->{fraction} = $fraction;

   # Continue computing the metrics, and call the callback with them.
   my $elapsed   = $now - $self->{start};
   my $remaining = 0;
   my $eta       = $now;
   if ( $completed > 0 && $completed <= $jobsize && $elapsed > 0 ) {
      my $rate = $completed / $elapsed;
      if ( $rate > 0 ) {
         $remaining = ($jobsize - $completed) / $rate;
         $eta       = $now + int($remaining);
      }
   }
   $self->{callback}->($fraction, $elapsed, $remaining, $eta, $completed);
}

# Returns the number rounded to the nearest lower $self->{interval}, for use
# with interval-based reporting.  For example, when you want to report every 5%,
# then 0% through 4% all return 0%; 5% through 9% return 5%; and so on.  The
# number needs to be passed as a fraction from 0 to 1.
sub fraction_modulo {
   my ( $self, $num ) = @_;
   $num *= 100; # Convert from fraction to percentage
   return sprintf('%d',
      sprintf('%d', $num / $self->{interval}) * $self->{interval});
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
# End Progress package
# ###########################################################################
