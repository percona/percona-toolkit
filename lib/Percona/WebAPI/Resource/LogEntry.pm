# This program is copyright 2013 Percona Inc.
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
# Percona::WebAPI::Resource::LogEntry package
# ###########################################################################
{
package Percona::WebAPI::Resource::LogEntry;

use Lmo;

has 'pid' => (
   is       => 'ro',
   isa      => 'Int',
   required => 1,
);

has 'service' => (
   is       => 'ro',
   isa      => 'Str',
   required => 0,
);

has 'data_ts' => (
   is       => 'ro',
   isa      => 'Int',
   required => 0,
);

has 'entry_ts' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'log_level' => (
   is       => 'ro',
   isa      => 'Int',
   required => 1,
);

has 'message' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

no Lmo;
1;
}
# ###########################################################################
# End Percona::WebAPI::Resource::LogEntry package
# ###########################################################################
