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
# DiskstatsGroupByDisk package
# ###########################################################################
{
# Package: DiskstatsGroupByDisk
# 

package DiskstatsGroupByDisk;

use warnings;
use strict;
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use base qw( Diskstats );

use POSIX qw( ceil );

sub new {
   my ($class, %args) = @_;
   my $self = $class->SUPER::new(%args);
   $self->{_iterations}   = 0;
   return $self;
}

# Prints out one line for each disk, summing over the interval from first to
# last sample.
sub group_by {
   my ($self, %args) = @_;
   my @optional_args = qw( header_callback rows_callback );
   my ($header_callback, $rows_callback) = $args{ @optional_args };

   $self->clear_state() unless $self->interactive();

   my $original_offset = ($args{filehandle} || ref($args{data}))
                       ? tell($args{filehandle} || $args{data})
                       : undef;

   my $lines_read = $self->parse_from(
      sample_callback => sub {
         my ($self, $ts) = @_;

         if ( $self->has_stats() ) {
            $self->{_iterations}++;
            if ($self->interactive() && $self->{_iterations} >= 2) {
               my $elapsed = ( $self->curr_ts()  || 0 )
                           - ( $self->first_ts() || 0 );
               if ( $ts > 0 && ceil($elapsed) >= $self->sample_time() ) {
                  $self->print_deltas(
                     header_callback => sub {
                        my ($self, @args) = @_;

                        if ( $self->force_header() ) {
                           my $method = $args{header_callback}
                                        || "print_header";
                           $self->$method(@args);
                        }
                        $self->set_force_header(undef);
                     },
                     rows_callback   => $args{rows_callback},
                  );
                  return;
               }
            }
         }
      },
      filehandle => $args{filehandle},
      filename   => $args{filename},
      data       => $args{data},
   );

   if ($self->interactive()) {
      # This is a guard against the weird but nasty situation where
      # we read several samples from the filehandle, but reach
      # the end of file before $elapsed >= $self->sample_time().
      # If that happens, we need to rewind the filehandle to
      # where we started, so subsequent attempts (i.e. when
      # the file has more data) have greater chances of succeeding,
      # and no data goes unreported.
      return $lines_read;
   }

   return if $self->{_iterations} < 2;

   $self->print_deltas(
      header_callback => $args{header_callback},
      rows_callback   => $args{rows_callback},
   );

   $self->clear_state();

   return $lines_read;
}

sub clear_state {
   my ($self, @args)   = @_;
   my $orig_print_h = $self->{force_header};
   $self->{_iterations} = 0;
   $self->SUPER::clear_state(@args);
   $self->{force_header} = $orig_print_h;
}

sub compute_line_ts {
   my ($self, %args) = @_;
   if ( $self->show_timestamps() ) {
      return $self->SUPER::compute_line_ts(%args);
   }
   else {
      return "{" . ($self->{_iterations} - 1) . "}";
   }
}

sub delta_against {
   my ($self, $dev) = @_;
   return $self->first_stats_for($dev);
}

sub ts_line_for_timestamp {
   my ($self) = @_;
   return $self->prev_ts_line();
}

sub delta_against_ts {
   my ($self) = @_;
   return $self->first_ts();
}

sub compute_in_progress {
   my ($self, $in_progress, $tot_in_progress) = @_;
   return $tot_in_progress / ($self->{_iterations} - 1);
}

1;
}
# ###########################################################################
# End DiskstatsGroupByDisk package
# ###########################################################################
