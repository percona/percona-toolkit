# This program is copyright 2012 Percona Ireland Ltd.
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
# IndexLength package
# ###########################################################################
{
# Package: IndexLength
# IndexLength get the key_len of a index.

package IndexLength;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $self = {
      Quoter => $args{Quoter},
   };

   return bless $self, $class;
}

# Returns the length of the index in bytes using only
# the first N left-most columns of the index.
sub index_length {
   my ($self, %args) = @_;
   my @required_args = qw(Cxn tbl index);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($cxn) = @args{@required_args};

   die "The tbl argument does not have a tbl_struct"
      unless exists $args{tbl}->{tbl_struct};
   die "Index $args{index} does not exist in table $args{tbl}->{name}"
      unless $args{tbl}->{tbl_struct}->{keys}->{$args{index}};

   my $index_struct = $args{tbl}->{tbl_struct}->{keys}->{$args{index}};
   my $index_cols   = $index_struct->{cols};
   my $n_index_cols = $args{n_index_cols};
   if ( !$n_index_cols || $n_index_cols > @$index_cols ) {
      $n_index_cols = scalar @$index_cols;
   }

   # Get the first row with non-NULL values.
   my $vals = $self->_get_first_values(
      %args,
      n_index_cols => $n_index_cols,
   );

   # Make an EXPLAIN query to scan the range and execute it.
   my $sql = $self->_make_range_query(
      %args,
      n_index_cols => $n_index_cols,
      vals         => $vals,
   );
   my $sth = $cxn->dbh()->prepare($sql);
   PTDEBUG && _d($sth->{Statement}, 'params:', @$vals);
   $sth->execute(@$vals);
   my $row = $sth->fetchrow_hashref();
   $sth->finish();
   PTDEBUG && _d('Range scan:', Dumper($row));
   return $row->{key_len}, $row->{key};
}

sub _get_first_values {
   my ($self, %args) = @_;
   my @required_args = qw(Cxn tbl index n_index_cols);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($cxn, $tbl, $index, $n_index_cols) = @args{@required_args};

   my $q = $self->{Quoter};

   # Select just the index columns.
   my $index_struct  = $tbl->{tbl_struct}->{keys}->{$index};
   my $index_cols    = $index_struct->{cols};
   my $index_columns = join (', ',
      map { $q->quote($_) } @{$index_cols}[0..($n_index_cols - 1)]);

   # Where no index column is null, because we can't > NULL.
   my @where;
   foreach my $col ( @{$index_cols}[0..($n_index_cols - 1)] ) {
      push @where, $q->quote($col) . " IS NOT NULL"
   }

   my $sql = "SELECT /*!40001 SQL_NO_CACHE */ $index_columns "
           . "FROM $tbl->{name} FORCE INDEX (" . $q->quote($index) . ") "
           . "WHERE " . join(' AND ', @where)
           . " ORDER BY $index_columns "
           . "LIMIT 1 /*key_len*/";  # only need 1 row
   PTDEBUG && _d($sql);
   my $vals = $cxn->dbh()->selectrow_arrayref($sql);
   return $vals;
}

sub _make_range_query {
   my ($self, %args) = @_;
   my @required_args = qw(tbl index n_index_cols vals);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tbl, $index, $n_index_cols, $vals) = @args{@required_args};

   my $q = $self->{Quoter};

   my $index_struct = $tbl->{tbl_struct}->{keys}->{$index};
   my $index_cols   = $index_struct->{cols};

   # All but the last index col = val.
   my @where;
   if ( $n_index_cols > 1 ) {
      # -1 for zero-index array as usual, then -1 again because
      # we don't want the last column; that's added below.
      foreach my $n ( 0..($n_index_cols - 2) ) {
         my $col = $index_cols->[$n];
         my $val = $vals->[$n];
         push @where, $q->quote($col) . " = ?";
      }
   }

   # The last index col > val.  This causes the range scan using just
   # the N left-most index columns.
   my $col = $index_cols->[$n_index_cols - 1];
   my $val = $vals->[-1];  # should only be as many vals as cols
   push @where, $q->quote($col) . " >= ?";

   my $sql = "EXPLAIN SELECT /*!40001 SQL_NO_CACHE */ * "
           . "FROM $tbl->{name} FORCE INDEX (" . $q->quote($index) . ") "
           . "WHERE " . join(' AND ', @where)
           . " /*key_len*/";
   return $sql;
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
# End IndexLength package
# ###########################################################################
