# This program is copyright 2013-2026 Percona LLC and/or its affiliates.
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
# You should have received a copy of the GNU General Public License, version 2
# along with this program; if not, see <https://www.gnu.org/licenses/>.
# ###########################################################################
# FakeSth package
# ###########################################################################
{
package FakeSth;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, $rows ) = @_;
   my $n_rows = $rows && ref $rows eq 'ARRAY' ? scalar @$rows : 0;
   my $self = {
      rows   => $rows,
      n_rows => $n_rows,
   };
   return bless $self, $class;
}

sub fetchall_arrayref {
   my ( $self ) = @_;
   return $self->{rows};
}

sub finish {
   return;
}

1;
}
# ###########################################################################
# End FakeSth package
# ###########################################################################
