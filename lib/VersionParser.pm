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
# VersionParser package
# ###########################################################################
{
# Package: VersionParser
# VersionParser parses a MySQL version string.
package VersionParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class ) = @_;
   bless {}, $class;
}

sub parse {
   my ( $self, $str ) = @_;
   my @version_parts = $str =~ m/(\d+)/g;
   # Turn a version like 5.5 into 5.5.0
   @version_parts = map { $_ || 0 } @version_parts[0..2];
   my $result = sprintf('%03d%03d%03d', @version_parts);
   PTDEBUG && _d($str, 'parses to', $result);
   return $result;
}

# Compares versions like 5.0.27 and 4.1.15-standard-log.  Caches version number
# for each DBH for later use.
sub version_cmp {
   my ($self, $dbh, $target, $cmp) = @_;
   my $version = $self->version($dbh);
   my $result;

   if ( $cmp eq 'ge' ) {
      $result = $self->{$dbh} ge $self->parse($target) ? 1 : 0;
   }
   elsif ( $cmp eq 'gt' ) {
      $result = $self->{$dbh} gt $self->parse($target) ? 1 : 0;
   }
   elsif ( $cmp eq 'eq' ) {
      $result = $self->{$dbh} eq $self->parse($target) ? 1 : 0;
   }
   elsif ( $cmp eq 'ne' ) {
      $result = $self->{$dbh} ne $self->parse($target) ? 1 : 0;
   }
   elsif ( $cmp eq 'lt' ) {
      $result = $self->{$dbh} lt $self->parse($target) ? 1 : 0;
   }
   elsif ( $cmp eq 'le' ) {
      $result = $self->{$dbh} le $self->parse($target) ? 1 : 0;
   }
   else {
      die "Asked for an unknown comparizon: $cmp"
   }

   PTDEBUG && _d($self->{$dbh}, $cmp, $target, ':', $result);
   return $result;
}

sub version_ge {
   my ( $self, $dbh, $target ) = @_;
   return $self->version_cmp($dbh, $target, 'ge');
}

sub version_gt {
   my ( $self, $dbh, $target ) = @_;
   return $self->version_cmp($dbh, $target, 'gt');
}

sub version_eq {
   my ( $self, $dbh, $target ) = @_;
   return $self->version_cmp($dbh, $target, 'eq');
}

sub version_ne {
   my ( $self, $dbh, $target ) = @_;
   return $self->version_cmp($dbh, $target, 'ne');
}

sub version_lt {
   my ( $self, $dbh, $target ) = @_;
   return $self->version_cmp($dbh, $target, 'lt');
}

sub version_le {
   my ( $self, $dbh, $target ) = @_;
   return $self->version_cmp($dbh, $target, 'le');
}

sub version {
   my ( $self, $dbh ) = @_;
   if ( !$self->{$dbh} ) {
      $self->{$dbh} = $self->parse(
         $dbh->selectrow_array('SELECT VERSION()'));
   }
   return $self->{$dbh};
}

# Returns DISABLED if InnoDB doesn't appear as YES or DEFAULT in SHOW ENGINES,
# BUILTIN if there is no innodb_version variable in SHOW VARIABLES, or
# <value> if there is an innodb_version variable in SHOW VARIABLES, or
# NO if SHOW ENGINES is broken or InnDB doesn't appear in it.
sub innodb_version {
   my ( $self, $dbh ) = @_;
   return unless $dbh;
   my $innodb_version = "NO";

   my ($innodb) =
      grep { $_->{engine} =~ m/InnoDB/i }
      map  {
         my %hash;
         @hash{ map { lc $_ } keys %$_ } = values %$_;
         \%hash;
      }
      @{ $dbh->selectall_arrayref("SHOW ENGINES", {Slice=>{}}) };
   if ( $innodb ) {
      PTDEBUG && _d("InnoDB support:", $innodb->{support});
      if ( $innodb->{support} =~ m/YES|DEFAULT/i ) {
         my $vars = $dbh->selectrow_hashref(
            "SHOW VARIABLES LIKE 'innodb_version'");
         $innodb_version = !$vars ? "BUILTIN"
                         :          ($vars->{Value} || $vars->{value});
      }
      else {
         $innodb_version = $innodb->{support};  # probably DISABLED or NO
      }
   }

   PTDEBUG && _d("InnoDB version:", $innodb_version);
   return $innodb_version;
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
# End VersionParser package
# ###########################################################################
