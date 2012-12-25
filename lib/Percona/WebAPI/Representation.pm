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

use JSON;

sub as_hashref {
   my $resource = shift;

   # Copy the object into a new hashref.
   my $as_hashref = { %$resource };

   # Delete the links because they're just for client-side use
   # and the caller should be sending this object, not getting it.
   delete $as_hashref->{links};

   return $as_hashref;
}

sub as_json {
   return encode_json(as_hashref(@_));
}


sub as_config {
   my $as_hashref = as_hashref(@_);
   my $config     = join("\n",
      map { defined $as_hashref->{$_} ?  "$_=$as_hashref->{$_}" : "$_" }
      sort keys %$as_hashref
   ) . "\n";
   return $config;
}

1;
}
# ###########################################################################
# End Percona::WebAPI::Representation package
# ###########################################################################
