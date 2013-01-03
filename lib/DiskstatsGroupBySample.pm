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
# DiskstatsGroupBySample package
# ###########################################################################
{
# Package: DiskstatsGroupBySample
#

package DiskstatsGroupBySample;

use warnings;
use strict;
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use base qw( Diskstats );

use POSIX qw( ceil );

sub new {
   my ( $class, %args ) = @_;
   my $self = $class->SUPER::new(%args);
   $self->{_iterations}        = 0;
   $self->{_save_curr_as_prev} = 0;
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

   if ( $ts > 0 && ceil($elapsed) >= $self->sample_time() ) {

      $self->print_deltas(
         # When grouping by samples, we don't usually show the device names,
         # only a count of how many devices each sample has, which causes the
         # columns' width change depending on simple invisible. That's uncalled
         # for, so we hardcode the width here
         # (6 is what the shell version used).
         max_device_length       => 6,
         header_callback         => sub {
            my ( $self, $header, @args ) = @_;

            if ( $self->force_header() ) {
               my $method = $args{header_callback} || "print_header";
               $self->$method( $header, @args );
               $self->set_force_header(undef);
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
      $self->set_prev_ts_line( $self->curr_ts_line() );
      $self->{_save_curr_as_prev} = 0;
   }
   return;
}

sub delta_against {
   my ( $self, $dev ) = @_;
   return $self->prev_stats_for($dev);
}

sub ts_line_for_timestamp {
   my ($self) = @_;
   return $self->prev_ts_line();
}

sub delta_against_ts {
   my ( $self ) = @_;
   return $self->prev_ts();
}

sub clear_state {
   my ( $self, @args )         = @_;
   $self->{_iterations}        = 0;
   $self->{_save_curr_as_prev} = 0;
   $self->SUPER::clear_state(@args);
}

sub compute_devs_in_group {
   my ($self) = @_;
   my $stats  = $self->stats_for();
   return scalar grep {
            # Got stats for that device, and it matches the devices re
            $stats->{$_} && $self->_print_device_if($_)
         } $self->ordered_devs;
}

sub compute_dev {
   my ( $self, $devs ) = @_;
   $devs ||= $self->compute_devs_in_group();
   return "{" . $devs . "}" if $devs > 1;
   return (grep { $self->_print_device_if($_) } $self->ordered_devs())[0];
}

# Terrible breach of encapsulation, but it'll have to do for the moment.
sub _calc_stats_for_deltas {
   my ( $self, $elapsed ) = @_;

   my $delta_for;

   foreach my $dev ( grep { $self->_print_device_if($_) } $self->ordered_devs() ) {
      my $curr    = $self->stats_for($dev);
      my $against = $self->delta_against($dev);

      next unless $curr && $against;

      my $delta = $self->_calc_delta_for( $curr, $against );
      $delta->{ios_in_progress} = $curr->[Diskstats::IOS_IN_PROGRESS];
      while ( my ( $k, $v ) = each %$delta ) {
         $delta_for->{$k} += $v;
      }
   }

   return unless $delta_for && %{$delta_for};

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

   $self->{_first_time_magic} = undef;
   if ( @{$self->{_nochange_skips}} ) {
      my $devs = join ", ", @{$self->{_nochange_skips}};
      PTDEBUG && _d("Skipping [$devs], haven't changed from the first sample");
      $self->{_nochange_skips} = [];
   }

   return \%stats;
}

sub compute_line_ts {
   my ($self, %args) = @_;
   if ( $self->show_timestamps() ) {
      @args{ qw( first_ts curr_ts ) } = @args{ qw( curr_ts first_ts ) }
   }
   return $self->SUPER::compute_line_ts(%args);
}

1;

}
# ###########################################################################
# End DiskstatsGroupBySample package
# ###########################################################################
