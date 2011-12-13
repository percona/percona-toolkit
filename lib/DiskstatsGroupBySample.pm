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

sub group_by {
   my $self = shift;
   $self->group_by_sample(@_);
}

# Prints out one line for each disk, summing over the interval from first to
# last sample.
sub group_by_sample {
   my ( $self,      %args )    = @_;
   my ( $header_cb, $rest_cb ) = $args{qw( header_cb rest_cb )};

   $self->clear_state;

   $self->parse_from(
      sample_callback =>
        sub { my ( $self, $ts ) = @_; $self->_sample_callback( $ts, %args ) },
      map( { ( $_ => $args{$_} ) } qw(filehandle filename data) ),
   );

   $self->clear_state;
}

sub _sample_callback {
   my ( $self, $ts, %args ) = @_;
   my $printed_a_line = 0;

   if ( $self->has_stats ) {
      $self->{_iterations}++;
   }

   my $elapsed =
     ( $self->current_ts() || 0 ) -
     ( $self->previous_ts() || 0 );

   if ( $ts > 0 && $elapsed >= $self->{interval} ) {

      $self->print_deltas(
         max_device_length => 6,
         header_cb         => sub {
            my ( $self, $header, @args ) = @_;
            if ( $self->{_print_header} ) {
               $self->{_print_header} = 0;
               if ( my $cb = $args{header_cb} ) {
                  $self->$cb( $header, @args );
               }
               else {
                  printf { $self->out_fh } $header . "\n", @args;
               }
            }
         },
         rest_cb => sub {
            my ( $self, $format, $cols, $stat ) = @_;
            if ( my $callback = $args{rest_cb} ) {
               $self->$callback( $format, $cols, $stat );
            }
            else {
               printf { $self->out_fh } $format . "\n",
                 @{$stat}{ qw( line_ts dev ), @$cols };
            }
            $printed_a_line = 1;
         }
      );
   }
   if ( $self->{_iterations} == 1 || $printed_a_line == 1 ) {
      $self->{_save_curr_as_prev} = 1;
      $self->_save_current_as_previous( $self->stats_for() );
      $self->{_save_curr_as_prev} = 0;
   }
}

sub delta_against {
   my ( $self, $dev ) = @_;
   return $self->previous_stats_for($dev);
}

sub delta_against_ts {
   my ( $self ) = @_;
   return $self->previous_ts();
}

sub clear_state {
   my ( $self, @args ) = @_;
   $self->{_iterations}        = 0;
   $self->{_save_curr_as_prev} = 0;
   $self->{_print_header}      = 1;
   $self->SUPER::clear_state(@args);
}

sub compute_devs_in_group {
   my ($self) = @_;
   return scalar grep 1, @{ $self->stats_for }{ $self->sorted_devs };
}

sub compute_dev {
   my ( $self, $dev ) = @_;
   return $self->compute_devs_in_group() > 1
     ? "{" . $self->compute_devs_in_group() . "}"
     : ( $self->sorted_devs )[0];
}

# Terrible breach of encapsulation, but it'll have to do for the moment.
sub _calc_stats_for_deltas {
   my ( $self, $elapsed ) = @_;

   my $delta_for;

   for my $dev ( grep { $self->dev_ok($_) } $self->sorted_devs ) {
      my $curr    = $self->stats_for($dev);
      my $against = $self->delta_against($dev);

      my $delta = $self->_calc_delta_for( $curr, $against );
      $delta->{ios_in_progress} = $curr->{ios_in_progress};
      while ( my ( $k, $v ) = each %$delta ) {
         $delta_for->{$k} += $v;
      }
   }

   my $in_progress = $delta_for->{ios_in_progress}; #$curr->{"ios_in_progress"};
   my $tot_in_progress = 0;    #$against->{"sum_ios_in_progress"} || 0;

   my $devs_in_group = $self->compute_devs_in_group;

   my %stats = (
      $self->_calc_read_stats( $delta_for, $elapsed, $devs_in_group ),
      $self->_calc_write_stats( $delta_for, $elapsed, $devs_in_group ),
      in_progress =>
        $self->compute_in_progress( $in_progress, $tot_in_progress ),
   );

   my %extras = $self->_calc_misc_stats( $delta_for, $elapsed, $devs_in_group, \%stats );
   while ( my ($k, $v) = each %extras ) {
      $stats{$k} = $v;
   }

   $stats{dev} = $self->compute_dev( \%stats );

   return \%stats;
}

1;

}
# ###########################################################################
# End DiskstatsGroupBySample package
# ###########################################################################
