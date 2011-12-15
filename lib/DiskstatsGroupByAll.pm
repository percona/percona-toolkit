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

sub group_by {
   my $self = shift;
   $self->group_by_all(@_);
}

sub group_by_all {
   my ($self, %args) = @_;

   if ( !$args{clear_state} ) {
      $self->clear_state();
   }

   if (!$self->interactive) {
      $self->parse_from(
         sample_callback => sub {
               $self->print_deltas(
                  map { ( $_ => $args{$_} ) } qw( header_cb rest_cb ),
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
                  header_cb => sub {
                     my $self = shift;
                     if ( $self->{_print_header} ) {
                        my $meth = $args{header_cb} || "print_header";
                        $self->$meth(@_);
                     }
                     $self->{_print_header} = undef;
                  },
                  rest_cb => $args{rest_cb},
               );
            },
         map( { ($_ => $args{$_}) } qw(filehandle filename data) ),
      );
      if (!$self->previous_ts) {
         seek $args{filehandle}, $orig, 0;
      }
      return;
   }
   $self->clear_state();
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
   return $self->previous_stats_for($dev);
}

sub delta_against_ts {
   my ($self) = @_;
   return $self->previous_ts();
}

1;
}
# ###########################################################################
# End DiskstatsGroupByAll package
# ###########################################################################
