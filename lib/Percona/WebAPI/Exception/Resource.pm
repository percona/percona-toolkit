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
# Percona::WebAPI::Exception::Resource package
# ###########################################################################
{
package Percona::WebAPI::Exception::Resource;

use Lmo;
use overload '""' => \&as_string;
use Data::Dumper;

has 'type' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'link' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'data' => (
   is       => 'ro',
   isa      => 'ArrayRef',
   required => 1,
);

has 'error' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

sub as_string {
   my $self = shift;
   chomp(my $error = $self->error);
   local $Data::Dumper::Indent    = 1;
   local $Data::Dumper::Sortkeys  = 1;
   local $Data::Dumper::Quotekeys = 0;
   return sprintf "Invalid %s resource from %s:\n\n%s\nError: %s\n\n",
      $self->type, $self->link, Dumper($self->data), $error;
}

no Lmo;
1;
}
# ###########################################################################
# End Percona::WebAPI::Exception::Resource package
# ###########################################################################
