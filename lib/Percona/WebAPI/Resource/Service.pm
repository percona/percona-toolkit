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
# Percona::WebAPI::Resource::Service package
# ###########################################################################
{
package Percona::WebAPI::Resource::Service;

use Lmo;

has 'ts' => (
   is       => 'ro',
   isa      => 'Int',
   required => 1,
);

has 'name' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'tasks' => (
   is       => 'ro',
   isa      => 'ArrayRef[Percona::WebAPI::Resource::Task]',
   required => 1,
);

has 'run_schedule' => (
   is       => 'ro',
   isa      => 'Str',
   required => 0,
);

has 'spool_schedule' => (
   is       => 'ro',
   isa      => 'Str',
   required => 0,
);

has 'meta' => (
   is       => 'ro',
   isa      => 'Bool',
   required => 0,
   default  => sub { return 0 },
);

has 'run_once' => (
   is       => 'ro',
   isa      => 'Bool',
   required => 0,
   default  => sub { return 0 },
);

has 'links' => (
   is       => 'rw',
   isa      => 'Maybe[HashRef]',
   required => 0,
   default  => sub { return {} },
);

sub BUILDARGS {
   my ($class, %args) = @_;
   if ( ref $args{tasks} eq 'ARRAY' ) {
      my @tasks;
      foreach my $run_hashref ( @{$args{tasks}} ) {
         my $task = Percona::WebAPI::Resource::Task->new(%$run_hashref);
         push @tasks, $task;
      }
      $args{tasks} = \@tasks;
   }
   return $class->SUPER::BUILDARGS(%args);
}

no Lmo;
1;
}
# ###########################################################################
# End Percona::WebAPI::Resource::Service package
# ###########################################################################
