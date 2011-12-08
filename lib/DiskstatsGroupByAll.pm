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
# DiskstatsGroupByAll package
# ###########################################################################
{
# Package: DiskstatsGroupByAll
# 

package DiskstatsGroupByAll;

use warnings;
use strict;
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use base qw( Diskstats );

sub group_by_all {
   my ($self, %args) = @_;
   $self->clear_state();
   $self->parse_from(
      ts_callback => sub {
            $self->print_deltas(
               map { ( $_ => $args{$_} ) } qw( header_cb rest_cb ),
            );
         },
      map( { ($_ => $args{$_}) } qw(filehandle filename data) ),
   );
   $self->clear_state();
}

sub compute_line_ts {
   my ($self, %args) = @_;
   return $args{first_ts} > 0
            ? sprintf("%5.1f", $args{current_ts} - $args{first_ts})
            : sprintf("%5.1f", 0);
}

sub delta_against {
   my ($self, $dev) = @_;
   return $self->previous_stats_for($dev);
}

sub compute_in_progress {
   my ($self, $in_progress, $tot_in_progress) = @_;
   return $in_progress;
}

1;
}
# ###########################################################################
# End DiskstatsGroupByAll package
# ###########################################################################
