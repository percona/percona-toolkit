# This program is copyright 2012-2013 Percona Inc.
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
# Lmo::Meta package
# ###########################################################################
{
# Package: Lmo::Meta
# Meta data implementation for Lmo.  Forked from 0.30 of Mo.
package Lmo::Meta;

use strict;
use warnings FATAL => 'all';

my %metadata_for;

sub new {
   shift;
   return Lmo::Meta::Class->new(@_);
}

sub metadata_for {
   my $self    = shift;
   my ($class) = @_;

   return $metadata_for{$class} ||= {};
}

{
   package Lmo::Meta::Class;

   sub new {
      my $class = shift;
      return bless { @_ }, $class
   }

   sub class { shift->{class} }

   sub attributes {
      my $self = shift;
      return keys %{Lmo::Meta->metadata_for($self->class)}
   }

   sub attributes_for_new {
      my $self = shift;
      my @attributes;

      my $class_metadata = Lmo::Meta->metadata_for($self->class);
      while ( my ($attr, $meta) = each %$class_metadata ) {
         if ( exists $meta->{init_arg} ) {
            push @attributes, $meta->{init_arg}
                  if defined $meta->{init_arg};
         }
         else {
            push @attributes, $attr;
         }
      }
      return @attributes;
   }
}

1;
}
# ###########################################################################
# End Lmo::Meta package
# ###########################################################################
