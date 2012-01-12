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
# DiskstatsGroupBySample package
# ###########################################################################
{
# Package: DiskstatsGroupBySample
#

package DiskstatsGroupBySample;

use warnings;
use strict;
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use base qw( Diskstats );

sub new {
   my ( $class, %args ) = @_;
   my $self = $class->SUPER::new(%args);
   $self->{_iterations}        = 0;
   $self->{_save_curr_as_prev} = 0;
   $self->{_print_header}      = 1;
   return $self;
}

# Prints out one line for each disk, summing over the interval from first to
# last sample.
sub group_by {
   my ( $self, %args ) = @_;
   my @optional_args   = qw( header_callback rows_callback );
   my ( $header_callback, $rows_callback ) = $args{ @optional_args };

   $self->clear_state() unless $self->interactive();

   $self->parse_from(
      # ->can comes from UNIVERSAL. Returns a coderef to the method, if found.
      # undef otherwise.
      # Basically \&func, but always in runtime, and allows overriding
      # the method in child classes.
      sample_callback => $self->can("_sample_callback"),
      filehandle      => $args{filehandle},
      filename        => $args{filename},
      data            => $args{data},
   );

   $self->clear_state() unless $self->interactive();
   return;
}

sub _sample_callback {
   my ( $self, $ts, %args ) = @_;
   my $printed_a_line = 0;

   if ( $self->has_stats() ) {
      $self->{_iterations}++;
   }

   my $elapsed = ($self->curr_ts() || 0)
               - ($self->prev_ts() || 0);

   if ( $ts > 0 && $elapsed >= $self->sample_time() ) {

      $self->print_deltas(
         # When grouping by samples, we don't usually show the device names,
         # only a count of how many devices each sample has, which causes the
         # columns' width change depending on simple invisible. That's uncalled
         # for, so we hardcode the width here
         # (6 is what the shell version used).
         max_device_length       => 6,
         header_callback         => sub {
            my ( $self, $header, @args ) = @_;

            if ( $self->{_print_header} ) {
               my $method = $args{header_callback} || "print_header";
               $self->$method( $header, @args );
               $self->{_print_header} = undef;
            }
         },
         rows_callback => sub {
            my ( $self, $format, $cols, $stat ) = @_;
            my $method = $args{rows_callback} || "print_rows";
            $self->$method( $format, $cols, $stat );
            $printed_a_line = 1;
         }
      );
   }
   if ( $self->{_iterations} == 1 || $printed_a_line == 1 ) {
      $self->{_save_curr_as_prev} = 1;
      $self->_save_curr_as_prev( $self->stats_for() );
      $self->{_save_curr_as_prev} = 0;
   }
   return;
}

sub delta_against {
   my ( $self, $dev ) = @_;
   return $self->prev_stats_for($dev);
}

sub delta_against_ts {
   my ( $self ) = @_;
   return $self->prev_ts();
}

sub clear_state {
   my ( $self, @args )         = @_;
   $self->{_iterations}        = 0;
   $self->{_save_curr_as_prev} = 0;
   $self->{_print_header}      = 1;
   $self->SUPER::clear_state(@args);
}

sub compute_devs_in_group {
   my ($self) = @_;
   my $stats  = $self->stats_for();
   my $re     = $self->device_regex();
   return scalar grep {
            # Got stats for that device, and it matches the devices re
            $stats->{$_} && $_ =~ $re
         } $self->ordered_devs;
}

sub compute_dev {
   my ( $self, $devs ) = @_;
   $devs ||= $self->compute_devs_in_group();
   return $devs > 1
     ? "{" . $devs . "}"
     : $self->{ordered_devs}->[0];
}

# Terrible breach of encapsulation, but it'll have to do for the moment.
sub _calc_stats_for_deltas {
   my ( $self, $elapsed ) = @_;

   my $delta_for;

   foreach my $dev ( grep { $self->dev_ok($_) } $self->ordered_devs ) {
      my $curr    = $self->stats_for($dev);
      my $against = $self->delta_against($dev);

      my $delta = $self->_calc_delta_for( $curr, $against );
      $delta->{ios_in_progress} = $curr->[Diskstats::ios_in_progress];
      while ( my ( $k, $v ) = each %$delta ) {
         $delta_for->{$k} += $v;
      }
   }

   my $in_progress     = $delta_for->{ios_in_progress};
   my $tot_in_progress = 0;
   my $devs_in_group   = $self->compute_devs_in_group() || 1;

   my %stats = (
      $self->_calc_read_stats(
         delta_for     => $delta_for,
         elapsed       => $elapsed,
         devs_in_group => $devs_in_group,
      ),
      $self->_calc_write_stats(
         delta_for     => $delta_for,
         elapsed       => $elapsed,
         devs_in_group => $devs_in_group,
      ),
      in_progress =>
         $self->compute_in_progress( $in_progress, $tot_in_progress ),
   );

   my %extras = $self->_calc_misc_stats(
      delta_for     => $delta_for,
      elapsed       => $elapsed,
      devs_in_group => $devs_in_group,
      stats         => \%stats,
   );

   @stats{ keys %extras } = values %extras;

   $stats{dev} = $self->compute_dev( $devs_in_group );

   return \%stats;
}

1;

}
# ###########################################################################
# End DiskstatsGroupBySample package
# ###########################################################################
