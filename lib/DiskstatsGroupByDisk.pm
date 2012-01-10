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
# DiskstatsGroupByDisk package
# ###########################################################################
{
# Package: DiskstatsGroupByDisk
# 

package DiskstatsGroupByDisk;

use warnings;
use strict;
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use base qw( Diskstats );

sub new {
   my ($class, %args) = @_;
   my $self = $class->SUPER::new(%args);
   $self->{_iterations}   = 0;
   $self->{_print_header} = 1;
   return $self;
}

sub group_by {
   my ($self, @args) = @_;
   $self->group_by_disk(@args);
}

# Prints out one line for each disk, summing over the interval from first to
# last sample.
sub group_by_disk {
   my ($self, %args) = @_;
   my ($header_callback, $rows_callback) = $args{ qw( header_callback rows_callback ) };

   $self->clear_state() unless $self->interactive();

   my $original_offset = $args{filehandle} ? tell($args{filehandle}) : undef;

   my $lines_read = $self->parse_from(
      sample_callback => sub {
         my ($self, $ts) = @_;

         if ( $self->has_stats() ) {
            $self->{_iterations}++;
            if ($self->interactive() && $self->{_iterations} >= 2) {
               my $elapsed = ( $self->curr_ts()  || 0 )
                           - ( $self->first_ts() || 0 );
               if ( $ts > 0 && $elapsed >= $self->sample_time() ) {
                  $self->print_deltas(
                     header_callback => sub {
                        my ($self, @args) = @_;

                        if ( $self->{_print_header} ) {
                           my $method = $args{header_callback}
                                        || "print_header";
                           $self->$method(@args);
                        }
                        $self->{_print_header} = undef;
                     },
                     rows_callback   => $args{rows_callback},
                  );

                  $self->{_iterations} = -1;
                  return;
               }
            }
         }
      },
      filehandle => $args{filehandle},
      filename   => $args{filename},
      data       => $args{data},
   );

   if ($self->interactive) {
      if ($self->{_iterations} == -1 && defined($original_offset)
            && eof($args{filehandle})) {
         $self->clear_state;
         seek $args{filehandle}, $original_offset, 0;
      }
      return $lines_read;
   }

   if ( $self->{_iterations} < 2 ) {
      return;
   }

   $self->print_deltas( 
      header_callback => $args{header_callback},
      rows_callback   => $args{rows_callback},
   );

   $self->clear_state();

   return $lines_read;
}

sub clear_state {
   my ($self, @args)   = @_;
   my $orig_print_h = $self->{_print_header};
   $self->{_iterations} = 0;
   $self->SUPER::clear_state(@args);
   $self->{_print_header} = $orig_print_h;
}

sub compute_line_ts {
   my ($self, %args) = @_;
   return "{" . ($self->{_iterations} - 1) . "}";
}

sub delta_against {
   my ($self, $dev) = @_;
   return $self->first_stats_for($dev);
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
