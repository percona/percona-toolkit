# This program is copyright 2007-2011 Baron Schwartz, 2011 Percona Inc.
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
# MockSth package
# ###########################################################################
{
# Package: MockSth
# MockSth simulates a DBI statement handle without a database connection.
package MockSth;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, @rows ) = @_;
   my $n_rows = scalar @rows;
   my $self = {
      cursor => 0,
      Active => $n_rows,
      rows   => \@rows,
      n_rows => $n_rows,
      NAME   => [],
   };
   return bless $self, $class;
}

sub reset {
   my ( $self ) = @_;
   $self->{cursor} = 0;
   $self->{Active} = $self->{n_rows};
   return;
}

sub fetchrow_hashref {
   my ( $self ) = @_;
   my $row;
   if ( $self->{cursor} < $self->{n_rows} ) {
      $row = $self->{rows}->[$self->{cursor}++];
   }
   $self->{Active} = $self->{cursor} < $self->{n_rows};
   return $row;
}

sub fetchall_arrayref {
   my ( $self ) = @_;
   my @rows;
   if ( $self->{cursor} < $self->{n_rows} ) {
      my @cols = @{$self->{NAME}};
      die "Cannot fetchall_arrayref() unless NAME is set" unless @cols;
      @rows =  map { [ @{$_}{@cols} ] }
         @{$self->{rows}}[ $self->{cursor}..($self->{n_rows} - 1) ];
      $self->{cursor} = $self->{n_rows};
   }
   $self->{Active} = $self->{cursor} < $self->{n_rows};
   return \@rows;
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
# End MockSth package
# ###########################################################################
