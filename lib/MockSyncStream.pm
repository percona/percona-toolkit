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
# MockSyncStream package
# ###########################################################################
{
# Package: MockSyncStream
# MockSyncStream simulates a <TableSyncStream> module.
# It's used by mk-upgrade to quickly compare result sets for any differences.
# If any are found, mk-upgrade writes all remaining rows to an outfile.
# This causes RowDiff::compare_sets() to terminate early.  So we don't actually
# sync anything.  Unlike TableSyncStream, we're not working with a table but an
# arbitrary query executed on two servers.
package MockSyncStream;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(query cols same_row not_in_left not_in_right) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   return bless { %args }, $class;
}

sub get_sql {
   my ( $self ) = @_;
   return $self->{query};
}

sub same_row {
   my ( $self, %args ) = @_;
   return $self->{same_row}->($args{lr}, $args{rr});
}

sub not_in_right {
   my ( $self, %args ) = @_;
   return $self->{not_in_right}->($args{lr});
}

sub not_in_left {
   my ( $self, %args ) = @_;
   return $self->{not_in_left}->($args{rr});
}

sub done_with_rows {
   my ( $self ) = @_;
   $self->{done} = 1;
}

sub done {
   my ( $self ) = @_;
   return $self->{done};
}

sub key_cols {
   my ( $self ) = @_;
   return $self->{cols};
}

# Do any required setup before executing the SQL (such as setting up user
# variables for checksum queries).
sub prepare {
   my ( $self, $dbh ) = @_;
   return;
}

# Return 1 if you have changes yet to make and you don't want the MockSyncer to
# commit your transaction or release your locks.
sub pending_changes {
   my ( $self ) = @_;
   return;
}

# RowDiff::key_cmp() requires $tlb and $key_cols but we're syncing query
# result sets not tables so we can't use TableParser.  The following sub
# uses sth attributes to return a pseudo table struct for the query's columns.
sub get_result_set_struct {
   my ( $dbh, $sth ) = @_;
   my @cols     = map { 
      my $name = $_;
      my $name_len = length($name);
      if ( $name_len > 64 ) {
         # https://bugs.launchpad.net/percona-toolkit/+bug/1060774
         # Chop off the left end because right-side data tends to be
         # the difference, e.g. load_the_canons vs. load_the_cantos.
         $name = substr($name, ($name_len - 64), 64);
      }
      $name;
   } @{$sth->{NAME}};
   my @types    = map { $dbh->type_info($_)->{TYPE_NAME} } @{$sth->{TYPE}};
   my @nullable = map { $dbh->type_info($_)->{NULLABLE} == 1 ? 1 : 0 } @{$sth->{TYPE}};

   my $struct   = {
      cols => \@cols, 
      # collation_for => {},  RowDiff::key_cmp() may need this.
   };

   for my $i ( 0..$#cols ) {
      my $col  = $cols[$i];
      my $type = $types[$i];
      $struct->{is_col}->{$col}      = 1;
      $struct->{col_posn}->{$col}    = $i;
      $struct->{type_for}->{$col}    = $type;
      $struct->{is_nullable}->{$col} = $nullable[$i];
      $struct->{is_numeric}->{$col} 
         = ($type =~ m/(?:(?:tiny|big|medium|small)?int|float|double|decimal|year)/ ? 1 : 0);

      # We no longer specify the (precision, scale) for double, float, and
      # decimal because DBD::mysql isn't reliable and defaults should work.
      # But char col sizes are important, e.g. varchar(16) and varchar(255)
      # won't hold the same values.
      # https://bugs.launchpad.net/percona-toolkit/+bug/926598
      $struct->{size}->{$col}
         = $type =~ m/(?:char|varchar)/ && $sth->{PRECISION}->[$i]
         ? "($sth->{PRECISION}->[$i])"
         : undef;
   }

   return $struct;
}

# Transforms a row fetched with DBI::fetchrow_hashref() into a
# row as if it were fetched with DBI::fetchrow_arrayref().  That is:
# the hash values (i.e. column values) are returned as an arrayref
# in the correct column order (because hashes are randomly ordered).
# This is used in mk-upgrade.
sub as_arrayref {
   my ( $sth, $row ) = @_;
   my @cols = @{$sth->{NAME}};
   my @row  = @{$row}{@cols};
   return \@row;
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
# End MockSyncStream package
# ###########################################################################
