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
# Percona::WebAPI::Representation package
# ###########################################################################
{
package Percona::WebAPI::Representation;

eval {
   require JSON;
};

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
   as_hashref
   as_json
   as_config
);

sub as_hashref {
   my ($resource, %args) = @_;

   # Copy the object into a new hashref.
   my $as_hashref = { %$resource };

   # Delete the links because they're just for client-side use
   # and the caller should be sending this object, not getting it.
   # But sometimes for testing we want to keep the links.
   if ( !defined $args{with_links} || !$args{with_links} ) {
      delete $as_hashref->{links};
   }

   return $as_hashref;
}

sub as_json {
   my ($resource, %args) = @_;

   my $json = $args{json} || JSON->new;
   $json->allow_blessed([]);
   $json->convert_blessed([]);

   my $text = $json->encode(
      ref $resource eq 'ARRAY' ? $resource : as_hashref($resource, %args)
   );
   if ( $args{json} && $text ) {  # for testing
      chomp($text);
      $text .= "\n";
   }
   return $text;
}

sub as_config {
   my $resource = shift;
   if ( !$resource->isa('Percona::WebAPI::Resource::Config') ) {
      die "Only Config resources can be represented as config.\n";
   }
   my $as_hashref = as_hashref($resource);
   my $options    = $as_hashref->{options};
   my $config     = join("\n",
      map { defined $options->{$_} ?  "$_=$options->{$_}" : "$_" }
      sort keys %$options
   ) . "\n";
   return $config;
}

1;
}
# ###########################################################################
# End Percona::WebAPI::Representation package
# ###########################################################################
