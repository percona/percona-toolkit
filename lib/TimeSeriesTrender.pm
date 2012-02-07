# This program is copyright 2010-2011 Percona Inc.
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
# TimeSeriesTrender package
# ###########################################################################
{
# Package: TimeSeriesTrender
# TimeSeriesTrender calculates trends in time.
package TimeSeriesTrender;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# Arguments:
#  *  callback    Subroutine to call when the time is set to the next larger
#                 increment.  Receives a hashref of the current timestamp's
#                 stats (see compute_stats()).
sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(callback) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = {
      %args,
      ts      => '',
      numbers => [],
   };
   return bless $self, $class;
}

# Set the current timestamp to be applied to all subsequent values received
# through add_number().  If the timestamp changes to the "next larger
# increment," then fire the callback.  It *is* possible for a timestamp to be
# less than one previously seen.  In such cases, we simply lump those
# time-series data points into the current timestamp's bucket.
sub set_time {
   my ( $self, $ts ) = @_;
   my $cur_ts = $self->{ts};
   if ( !$cur_ts ) {
      $self->{ts} = $ts;
   }
   elsif ( $ts gt $cur_ts ) {
      my $statistics = $self->compute_stats($cur_ts, $self->{numbers});
      $self->{callback}->($statistics);
      $self->{numbers} = [];
      $self->{ts}      = $ts;
   }
   # If $cur_ts > $ts, then we do nothing -- we do not want $self->{ts} to ever
   # decrease!
}

# Add a number to the current batch defined by the current timestamp, which is
# set by set_time().
sub add_number {
   my ( $self, $number ) = @_;
   push @{$self->{numbers}}, $number;
}

# Compute the desired statistics over the set of numbers, which is passed in as
# an arrayref.  Returns a hashref.
sub compute_stats {
   my ( $self, $ts, $numbers ) = @_;
   my $cnt = scalar @$numbers;
   my $result = {
      ts    => $ts,
      cnt   => 0,
      sum   => 0,
      min   => 0,
      max   => 0,
      avg   => 0,
      stdev => 0,
   };
   return $result unless $cnt;
   my ( $sum, $min, $max, $sumsq ) = (0, 2 ** 32, 0, 0);
   foreach my $num ( @$numbers ) {
      $sum   += $num;
      $min    = $num < $min ? $num : $min;
      $max    = $num > $max ? $num : $max;
      $sumsq += $num * $num;
   }
   my $avg   = $sum / $cnt;
   my $var   = $sumsq / $cnt - ( $avg * $avg );
   my $stdev = $var > 0 ? sqrt($var) : 0;
   # TODO: must compute the significant digits of the input, and use that to
   # round the output appropriately.
   @{$result}{qw(cnt sum min max avg stdev)}
      = ($cnt, $sum, $min, $max, $avg, $stdev);
   return $result;
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
# End TimeSeriesTrender package
# ###########################################################################
