# This program is copyright 2011 Percona Ireland Ltd.
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
# WeightedAvgRate package
# ###########################################################################
{
# Package: WeightedAvgRate
# WeightedAvgRate calculates and returns a weighted average rate.
package WeightedAvgRate;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# Sub: new
#
# Required Arguments:
#   target_t   - Target time for t in <update()>
#
# Optional Arguments:
#   weight - Weight of previous n/t values (default 0.75).
#
# Returns:
#   WeightedAvgRate
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(target_t);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $self = {
      %args,
      avg_n  => 0,
      avg_t  => 0,
      weight => $args{weight} || 0.75,
   };

   return bless $self, $class;
}

# Sub: update
#   Update weighted average rate.  Param n is generic; it's how many of
#   whatever the caller is doing (rows, checksums, etc.).  Param s is how
#   long this n took, in seconds (hi-res or not).
#
# Parameters:
#   n - Number of operations (rows, etc.)
#   t - Amount of time in seconds that n took
#
# Returns:
#   n adjust to meet target_t based on weighted decaying avg rate
sub update {
   my ($self, $n, $t) = @_;
   PTDEBUG && _d('Master op time:', $n, 'n /', $t, 's');

   if ( $self->{avg_n} && $self->{avg_t} ) {
      $self->{avg_n}    = ($self->{avg_n} * $self->{weight}) + $n;
      $self->{avg_t}    = ($self->{avg_t} * $self->{weight}) + $t;
      $self->{avg_rate} = $self->{avg_n}  / $self->{avg_t};
      PTDEBUG && _d('Weighted avg rate:', $self->{avg_rate}, 'n/s');
   }
   else {
      $self->{avg_n}    = $n;
      $self->{avg_t}    = $t;
      $self->{avg_rate} = $self->{avg_n}  / $self->{avg_t};
      PTDEBUG && _d('Initial avg rate:', $self->{avg_rate}, 'n/s');
   }

   my $new_n = int($self->{avg_rate} * $self->{target_t});
   PTDEBUG && _d('Adjust n to', $new_n);
   return $new_n;
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
# End WeightedAvgRate package
# ###########################################################################
