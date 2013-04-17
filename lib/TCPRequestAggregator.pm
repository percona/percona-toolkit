# This program is copyright 2011 Baron Schwartz, 2011 Percona Ireland Ltd.
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
# TCPRequestAggregator package
# ###########################################################################
{
# Package: TCPRequestAggregator
# TCPRequestAggregator aggregates TCP requests from tcpdump files.
package TCPRequestAggregator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use List::Util qw(sum);
use Data::Dumper;

# Required arguments: interval, quantile
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(interval quantile);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      buffer             => [],
      last_weighted_time => 0,
      last_busy_time     => 0,
      last_completions   => 0,
      current_ts         => 0,
      %args,
   };
   return bless $self, $class;
}

# This method accepts an open filehandle and callback functions.  It reads
# events from the filehandle and calls the callbacks with each event.  $misc is
# some placeholder for the future and for compatibility with other query
# sources.
#
# The input is the output of mk-tcp-model, like so:
#
#   21 1301957863.820001 1301957863.820169  0.000168 10.10.18.253:58297
#   22 1301957863.821677 1301957863.821839  0.000162 10.10.18.253:43608
#   23 1301957863.822890 1301957863.823074  0.000184 10.10.18.253:52726
#   24 1301957863.822895 1301957863.823160  0.000265 10.10.18.253:58297
#
# Each event is a hashref of attribute => value pairs as defined in
# mk-tcp-model's documentation.
sub parse_event {
   my ( $self, %args ) = @_;
   my @required_args = qw(next_event tell);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($next_event, $tell) = @args{@required_args};

   my $pos_in_log = $tell->();
   my $buffer = $self->{buffer};
   $self->{last_pos_in_log} ||= $pos_in_log;

   EVENT:
   while ( 1 ) {
      PTDEBUG && _d("Beginning a loop at pos", $pos_in_log);
      my ( $id, $start, $elapsed );

      my ($timestamp, $direction);
      if ( $self->{pending} ) {
         ( $id, $start, $elapsed ) = @{$self->{pending}};
         PTDEBUG && _d("Pulled from pending", @{$self->{pending}});
      }
      elsif ( defined(my $line = $next_event->()) ) {
         # Split the line into ID, start, end, elapsed, and host:port
         my ($end, $host_port);
         ( $id, $start, $end, $elapsed, $host_port ) = $line =~ m/(\S+)/g;
         @$buffer = sort { $a <=> $b } ( @$buffer, $end );
         PTDEBUG && _d("Read from the file", $id, $start, $end, $elapsed, $host_port);
         PTDEBUG && _d("Buffer is now", @$buffer);
      }
      if ( $start ) { # Test that we got a line; $id can be 0.
         # We have a line to work on.  The next event we need to process is the
         # smaller of a) the arrival recorded in the $start of the line we just
         # read, or b) the first completion recorded in the completions buffer.
         if ( @$buffer && $buffer->[0] < $start ) {
            $direction       = 'C'; # Completion
            $timestamp       = shift @$buffer;
            $self->{pending} = [ $id, $start, $elapsed ];
            $id = $start = $elapsed = undef;
            PTDEBUG && _d("Completion: using buffered end value", $timestamp);
            PTDEBUG && _d("Saving line to pending", @{$self->{pending}});
         }
         else {
            $direction       = 'A'; # Arrival
            $timestamp       = $start;
            $self->{pending} = undef;
            PTDEBUG && _d("Deleting pending line");
            PTDEBUG && _d("Arrival: using the line");
         }
      }
      elsif ( @$buffer ) {
         $direction = 'C';
         $timestamp = shift @$buffer;
         PTDEBUG && _d("No more lines, reading from buffer", $timestamp);
      }
      else { # We hit EOF.
         PTDEBUG && _d("No more lines, no more buffered end times");
         if ( $self->{in_prg} ) {
            die "Error: no more lines, but in_prg = $self->{in_prg}";
         }
         if ( defined $self->{t_start}
                && defined $self->{current_ts}
                && $self->{t_start} < $self->{current_ts} )
         {
            PTDEBUG && _d("Returning event based on what's been seen");
            return $self->make_event($self->{t_start}, $self->{current_ts});
         }
         else {
            PTDEBUG && _d("No further events to make");
            return;
         }
      }

      # The notation used here is T_start for start of observation time (T).
      # The divide, int(), and multiply effectively truncates the value to
      # $interval precision.
      my $t_start = int($timestamp / $self->{interval}) * $self->{interval};
      $self->{t_start} ||= $timestamp; # Not $t_start; that'd skew 1st interval.
      PTDEBUG && _d("Timestamp", $timestamp, "interval start time", $t_start);

      # If $timestamp is not within the current interval, then we need to save
      # everything for later, compute stats for the rest of this interval, and
      # return an event.  The next time we are called, we'll begin the next
      # interval.  
      if ( $t_start > $self->{t_start} ) {
         PTDEBUG && _d("Timestamp doesn't belong to this interval");
         # We need to compute how much time is left in this interval, and add
         # that much busy_time and weighted_time to the running totals, but only
         # if there is some request in progress.
         if ( $self->{in_prg} ) {
            PTDEBUG && _d("Computing from", $self->{current_ts}, "to", $t_start);
            $self->{busy_time}     += $t_start - $self->{current_ts};
            $self->{weighted_time} += ($t_start - $self->{current_ts}) * $self->{in_prg};
         }

         if ( @$buffer && $buffer->[0] < $t_start ) {
            die "Error: completions for interval remain unprocessed";
         }

         # Reset running totals and last-time-seen stuff for next iteration,
         # re-buffer the completion or replace the line onto pending, then
         # return the event.
         my $event                = $self->make_event($self->{t_start}, $t_start);
         $self->{last_pos_in_log} = $pos_in_log;
         if ( $start ) {
            $self->{pending} = [ $id, $start, $elapsed ];
         }
         else {
            unshift @$buffer, $timestamp;
         }
         return $event;
      }

      # Otherwise, we need to compute the running sums and keep looping.
      else {
         if ( $self->{in_prg} ) {
            # $self->{current_ts} is intitially 0, which would seem likely to
            # skew this computation.  But $self->{in_prg} will be 0 also, and
            # $self->{current_ts} will get set immediately after this, so
            # anytime this if() block runs, it'll be OK.
            PTDEBUG && _d("Computing from", $self->{current_ts}, "to", $timestamp);
            $self->{busy_time}     += $timestamp - $self->{current_ts};
            $self->{weighted_time} += ($timestamp - $self->{current_ts}) * $self->{in_prg};
         }
         $self->{current_ts} = $timestamp;
         if ( $direction eq 'A' ) {
            PTDEBUG && _d("Direction A", $timestamp);
            ++$self->{in_prg};
            if ( defined $elapsed ) {
               push @{$self->{response_times}}, $elapsed;
            }
         }
         else {
            PTDEBUG && _d("Direction C", $timestamp);
            --$self->{in_prg};
            ++$self->{completions};
         }
      }

      $pos_in_log = $tell->();
   } # EVENT

   $args{oktorun}->(0) if $args{oktorun};
   return;
}

# Makes an event and returns it.  Arguments:
#  $t_start -- the start of the observation period for this event.
#  $t_end   -- the end of the observation period for this event.
sub make_event {
   my ( $self, $t_start, $t_end ) = @_;

   # Prep a couple of things...
   my $quantile_cutoff = sprintf( "%.0f", # Round to nearest int
      scalar( @{ $self->{response_times} } ) * $self->{quantile} );
   my @times = sort { $a <=> $b } @{ $self->{response_times} };
   my $arrivals = scalar(@times);
   my $sum_times = sum( @times );
   my $mean_times = ($sum_times || 0) / ($arrivals || 1);
   my $var_times = 0;
   if ( @times ) {
      $var_times = sum( map { ($_ - $mean_times) **2 } @times ) / $arrivals;
   }

   # Compute the parts of the event we'll return.
   my $e_ts
      = int( $self->{current_ts} / $self->{interval} ) * $self->{interval};
   my $e_concurrency = sprintf( "%.6f",
           ( $self->{weighted_time} - $self->{last_weighted_time} )
         / ( $t_end - $t_start ) );
   my $e_arrivals   = $arrivals;
   my $e_throughput = sprintf( "%.6f", $e_arrivals / ( $t_end - $t_start ) );
   my $e_completions
      = ( $self->{completions} - $self->{last_completions} );
   my $e_busy_time
      = sprintf( "%.6f", $self->{busy_time} - $self->{last_busy_time} );
   my $e_weighted_time = sprintf( "%.6f",
      $self->{weighted_time} - $self->{last_weighted_time} );
   my $e_sum_time = sprintf("%.6f", $sum_times || 0);
   my $e_variance_mean = sprintf("%.6f", $var_times / ($mean_times || 1));
   my $e_quantile_time = sprintf("%.6f", $times[ $quantile_cutoff - 1 ] || 0);

   # Construct the event
   my $event = {
      ts            => $e_ts,
      concurrency   => $e_concurrency,
      throughput    => $e_throughput,
      arrivals      => $e_arrivals,
      completions   => $e_completions,
      busy_time     => $e_busy_time,
      weighted_time => $e_weighted_time,
      sum_time      => $e_sum_time,
      variance_mean => $e_variance_mean,
      quantile_time => $e_quantile_time,
      pos_in_log    => $self->{last_pos_in_log},
      obs_time      => sprintf("%.6f", $t_end - $t_start),
   };

   $self->{t_start}            = $t_end;  # Not current_timestamp!
   $self->{current_ts}         = $t_end;  # Next iteration will begin at boundary
   $self->{last_weighted_time} = $self->{weighted_time};
   $self->{last_busy_time}     = $self->{busy_time};
   $self->{last_completions}   = $self->{completions};
   $self->{response_times}     = [];

   PTDEBUG && _d("Event is", Dumper($event));
   return $event;
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
# End TCPRequestAggregator package
# ###########################################################################
