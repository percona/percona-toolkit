# This program is copyright 2009-2011 Percona Ireland Ltd.
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
# ExecutionThrottler package
# ###########################################################################
{
# Package: ExecutionThrottler
# ExecutionThrottle slows program execution if a threshold is exceeded.
package ExecutionThrottler;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use List::Util qw(sum min max);
use Time::HiRes qw(time);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# Arguments:
#   * rate_max   scalar: maximum allowable execution rate
#   * get_rate   subref: callback to get the current execution rate
#   * check_int  scalar: check interval in seconds for calling get_rate()
#   * step       scalar: incr/decr skip_prob in step increments
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(rate_max get_rate check_int step);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = {
      step       => 0.05,  # default
      %args, 
      rate_ok    => undef,
      last_check => undef,
      stats      => {
         rate_avg     => 0,
         rate_samples => [],
      },
      int_rates  => [],
      skip_prob  => 0.0,
   };

   return bless $self, $class;
}

sub throttle {
   my ( $self, %args ) = @_;
   my $time = $args{misc}->{time} || time;
   if ( $self->_time_to_check($time) ) {
      my $rate_avg = (sum(@{$self->{int_rates}})   || 0)
                   / (scalar @{$self->{int_rates}} || 1);
      my $running_avg = $self->_save_rate_avg($rate_avg);
      PTDEBUG && _d('Average rate for last interval:', $rate_avg);

      if ( $args{stats} ) {
         $args{stats}->{throttle_checked_rate}++;
         $args{stats}->{throttle_rate_avg} = sprintf '%.2f', $running_avg;
      }

      @{$self->{int_rates}} = ();

      if ( $rate_avg > $self->{rate_max} ) {
         # Rates is too high; increase the probability that the event
         # will be skipped.
         $self->{skip_prob} += $self->{step};
         $self->{skip_prob}  = 1.0 if $self->{skip_prob} > 1.0;
         PTDEBUG && _d('Rate max exceeded');
         $args{stats}->{throttle_rate_max_exceeded}++ if $args{stats};
      }
      else {
         # The rate is ok; decrease the probability that the event
         # will be skipped.
         $self->{skip_prob} -= $self->{step};
         $self->{skip_prob} = 0.0 if $self->{skip_prob} < 0.0;
         $args{stats}->{throttle_rate_ok}++ if $args{stats};
      }

      PTDEBUG && _d('Skip probability:', $self->{skip_prob});
      $self->{last_check} = $time;
   }
   else {
      my $current_rate = $self->{get_rate}->();
      push @{$self->{int_rates}}, $current_rate;
      if ( $args{stats} ) {
         $args{stats}->{throttle_rate_min} = min(
            ($args{stats}->{throttle_rate_min} || ()), $current_rate);
         $args{stats}->{throttle_rate_max} = max(
            ($args{stats}->{throttle_rate_max} || ()), $current_rate);
      }
      PTDEBUG && _d('Current rate:', $current_rate);
   } 

   # rand() returns a fractional value between [0,1).  If skip_prob is
   # 0 then, then no queries will be skipped.  If its 1.0, then all queries
   # will be skipped.  skip_prop is adjusted above; it depends on the
   # average rate.
   if ( $args{event} ) {
      $args{event}->{Skip_exec} = $self->{skip_prob} <= rand() ? 'No' : 'Yes';
   }

   return $args{event};
}

sub _time_to_check {
   my ( $self, $time ) = @_;
   if ( !$self->{last_check} ) {
      $self->{last_check} = $time;
      return 0;
   }
   return $time - $self->{last_check} >= $self->{check_int} ? 1 : 0;
}

sub rate_avg {
   my ( $self ) = @_;
   return $self->{stats}->{rate_avg} || 0;
}

sub skip_probability {
   my ( $self ) = @_;
   return $self->{skip_prob};
}

sub _save_rate_avg {
   my ( $self, $rate ) = @_;
   my $samples  = $self->{stats}->{rate_samples};
   push @$samples, $rate;
   shift @$samples if @$samples > 1_000;
   $self->{stats}->{rate_avg} = sum(@$samples) / (scalar @$samples);
   return $self->{stats}->{rate_avg} || 0;
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
# End ExecutionThrottler package
# ###########################################################################
