# This program is copyright 2009-2011 Percona Inc.
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
# CompareTableStructs package $Revision: 6785 $
# ###########################################################################
{
# Package: CompareTableStructs
# CompareTableStructs compares CREATE TABLE defs.
package CompareTableStructs;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
   };
   return bless $self, $class;
}

sub before_execute {
   my ( $self, %args ) = @_;
   return;
}

sub execute {
   my ( $self, %args ) = @_;
   return;
}

sub after_execute {
   my ( $self, %args ) = @_;
   return;
}

sub compare {
   my ( $s1, $s2 ) = @_;
   die "I need a s1 argument" unless defined $s1;
   die "I need a s2 argument" unless defined $s2;

   my $rank_inc = 0;
   my @reasons  = ();

   # Compare number of columns.
   if ( scalar @{$s1->{cols}} != scalar @{$s2->{cols}} ) {
      my $inc = 2 * abs( scalar @{$s1->{cols}} - scalar @{$s2->{cols}} );
      $rank_inc += $inc;
      push @reasons, 'Tables have different columns counts: '
         . scalar @{$s1->{cols}} . ' columns on host1, '
         . scalar @{$s2->{cols}} . " columns on host2 (rank+$inc)";
   }

   # Compare column types.
   my %host1_missing_cols = %{$s2->{type_for}};  # Make a copy to modify.
   my @host2_missing_cols;
   foreach my $col ( keys %{$s1->{type_for}} ) {
      if ( exists $s2->{type_for}->{$col} ) {
         if ( $s1->{type_for}->{$col} ne $s2->{type_for}->{$col} ) {
            $rank_inc += 3;
            push @reasons, "Types for $col column differ: "
               . "'$s1->{type_for}->{$col}' on host1, "
               . "'$s2->{type_for}->{$col}' on host2 (rank+3)";
         }
         delete $host1_missing_cols{$col};
      }
      else {
         push @host2_missing_cols, $col;
      }
   }

   foreach my $col ( @host2_missing_cols ) {
      $rank_inc += 5;
      push @reasons, "Column $col exists on host1 but not on host2 (rank+5)";
   }
   foreach my $col ( keys %host1_missing_cols ) {
      $rank_inc += 5;
      push @reasons, "Column $col exists on host2 but not on host1 (rank+5)";
   }

   return $rank_inc, @reasons;
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
# End CompareTableStructs package
# ###########################################################################
