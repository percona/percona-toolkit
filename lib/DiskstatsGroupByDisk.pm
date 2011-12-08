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
   $self->{iterations} = 0;
   return $self;
}

# Prints out one line for each disk, summing over the interval from first to
# last sample.
sub group_by_disk {
   my ($self, %args)         = @_;
   my ($header_cb, $rest_cb) = $args{ qw( header_cb rest_cb ) };

   $self->clear_state;

   $self->parse_from(
      ts_callback => sub {
         if ( $self->has_stats ) {
            $self->{iterations}++
         }
      },
      map({ ($_ => $args{$_}) } qw(filehandle filename data)),
   );

   if ( $self->{iterations} < 2 ) {
      return;
   }
   $self->print_deltas( map( { ( $_ => $args{$_} ) } qw( header_cb rest_cb ) ) );

   $self->clear_state;
}

sub clear_state {
   my ($self, @args) = @_;
   $self->{iterations} = 0;
   $self->SUPER::clear_state(@args);
}

sub compute_line_ts {
   my ($self, %args) = @_;
   return "{" . ($self->{iterations} - 1) . "}";
}

sub delta_against {
   my ($self, $dev) = @_;
   return $self->first_stats_for($dev);
}

sub compute_in_progress {
   my ($self, $in_progress, $tot_in_progress) = @_;
   return $tot_in_progress / ($self->{iterations} - 1);
}

1;
}
# ###########################################################################
# End DiskstatsGroupByDisk package
# ###########################################################################
