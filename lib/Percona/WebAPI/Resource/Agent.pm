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
# Percona::WebAPI::Resource::Agent package
# ###########################################################################
{
package Percona::WebAPI::Resource::Agent;

use Lmo;

has 'uuid' => (
   is       => 'ro',
   isa      => 'Str',
   required => 0,
);

has 'username' => (
   is       => 'rw',
   isa      => 'Str',
   required => 0,
   default  => sub { return $ENV{USER} || $ENV{LOGNAME} },
);

has 'hostname' => (
   is       => 'rw',
   isa      => 'Str',
   required => 0,
   default  => sub {
      chomp(my $hostname = `hostname`);
      return $hostname;
   },
);

has 'alias' => (
   is       => 'rw',
   isa      => 'Str',
   required => 0,
);

has 'versions' => (
   is       => 'rw',
   isa      => 'Maybe[HashRef]',
   required => 0,
);

has 'links' => (
   is       => 'rw',
   isa      => 'Maybe[HashRef]',
   required => 0,
   default  => sub { return {} },
);

sub name {
   my ($self) = @_;
   return $self->alias || $self->hostname || $self->uuid || 'Unknown';
}

no Lmo;
1;
}
# ###########################################################################
# End Percona::WebAPI::Resource::Agent package
# ###########################################################################
