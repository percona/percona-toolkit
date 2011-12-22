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

   if (!$self->interactive) {
      $self->parse_from(
         sample_callback => sub {
               $self->print_deltas(
                  map { ( $_ => $args{$_} ) }
                     qw( header_callback rest_callback ),
               );
            },
         map( { ($_ => $args{$_}) } qw(filehandle filename data) ),
      );
   }
   else {
      my $orig = tell $args{filehandle};
      $self->parse_from(
         sample_callback => sub {
               $self->print_deltas(
                  header_callback => sub {
                     my $self = shift;
                     if ( $self->{_print_header} ) {
                        my $meth = $args{header_callback} || "print_header";
                        $self->$meth(@_);
                     }
                     $self->{_print_header} = undef;
                  },
                  rest_callback => $args{rest_callback},
               );
            },
         map( { ($_ => $args{$_}) } qw(filehandle filename data) ),
      );
      if (!$self->prev_ts) {
         seek $args{filehandle}, $orig, 0;
      }
      return;
   }
   $self->clear_state();
}

# The next methods are all overrides!

sub group_by {
   my $self = shift;
   $self->group_by_all(@_);
}

sub clear_state {
   my $self = shift;
   if (!$self->interactive()) {
      $self->SUPER::clear_state(@_);
   }
   else {
      my $orig_print_header = $self->{_print_header};
      $self->SUPER::clear_state(@_);
      $self->{_print_header} = $orig_print_header;
   }
}

sub delta_against {
   my ($self, $dev) = @_;
   return $self->prev_stats_for($dev);
}

sub delta_against_ts {
   my ($self) = @_;
   return $self->prev_ts();
}

sub compute_line_ts {
   my ($self, %args) = @_;
   if ( $self->interactive() ) {
      # In interactive mode, we always compare against the previous sample,
      # but the default is to compare against the first.
      # This is generally a non-issue, because it can only happen
      # when there are more than two samples left to parse in the file,
      # which can only happen when someone sets a redisplay or sampling
      # interval (or both) too high.
      $args{first_ts} = $self->prev_ts();
   }
   return $self->SUPER::compute_line_ts(%args);
}

1;
}
# ###########################################################################
# End DiskstatsGroupByAll package
# ###########################################################################
