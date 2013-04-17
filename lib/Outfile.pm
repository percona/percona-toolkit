# This program is copyright 2009-2011 Percona Ireland Ltd.
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
# Outfile package
# ###########################################################################
{
# Package: Outfile
# Outfile writes rows to a file in SELECT INTO OUTFILE format.
package Outfile;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = {};
   return bless $self, $class;
}

# Print out in SELECT INTO OUTFILE format.
# $rows is an arrayref from DBI::selectall_arrayref().
sub write {
   my ( $self, $fh, $rows ) = @_;
   foreach my $row ( @$rows ) {
      print $fh escape($row), "\n"
         or die "Cannot write to outfile: $OS_ERROR\n";
   }
   return;
}

# Formats a row the same way SELECT INTO OUTFILE does by default.  This is
# described in the LOAD DATA INFILE section of the MySQL manual,
# http://dev.mysql.com/doc/refman/5.0/en/load-data.html
sub escape {
   my ( $row ) = @_;
   return join("\t", map {
      s/([\t\n\\])/\\$1/g if defined $_;  # Escape tabs etc
      defined $_ ? $_ : '\N';             # NULL = \N
   } @$row);
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End Outfile package
# ###########################################################################
