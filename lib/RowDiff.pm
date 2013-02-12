# This program is copyright 2007-2011 Baron Schwartz, 2011 Percona Ireland Ltd.
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
# RowDiff package
# ###########################################################################
{
# Package: RowDiff
# RowDiff compares two sets of rows to find ones that are different.
package RowDiff;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# Required args:
#   * dbh           obj: dbh used for collation-specific string comparisons
# Optional args:
#   * same_row      Callback when rows are identical
#   * not_in_left   Callback when right row is not in the left
#   * not_in_right  Callback when left row is not in the right
#   * key_cmp       Callback when a column value differs
#   * done          Callback that stops compare_sets() if it returns true
#   * trf           Callback to transform numeric values before comparison
sub new {
   my ( $class, %args ) = @_;
   die "I need a dbh" unless $args{dbh};
   my $self = { %args };
   return bless $self, $class;
}

# Arguments:
#   * left_sth    obj: sth
#   * right_sth   obj: sth
#   * syncer      obj: TableSync* module
#   * tbl_struct  hashref: table struct from TableParser::parser()
# Iterates through two sets of rows and finds differences.  Calls various
# methods on the $syncer object when it finds differences, passing these
# args and hashrefs to the differing rows ($lr and $rr).
sub compare_sets {
   my ( $self, %args ) = @_;
   my @required_args = qw(left_sth right_sth syncer tbl_struct);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $left_sth   = $args{left_sth};
   my $right_sth  = $args{right_sth};
   my $syncer     = $args{syncer};
   my $tbl_struct = $args{tbl_struct};

   my ($lr, $rr);    # Current row from the left/right sths.
   $args{key_cols} = $syncer->key_cols();  # for key_cmp()

   # We have to manually track if the left or right sth is done
   # fetching rows because sth->{Active} is always true with
   # DBD::mysql v3. And we cannot simply while ( $lr || $rr )
   # because in the case where left and right have the same key,
   # we do this:
   #    $lr = $rr = undef; # Fetch another row from each side.
   # Unsetting both $lr and $rr there would cause while () to
   # terminate. (And while ( $lr && $rr ) is not what we want
   # either.) Furthermore, we need to avoid trying to fetch more
   # rows if there are none to fetch because doing this would
   # cause a DBI error ("fetch without execute"). That's why we
   # make these checks:
   #    if ( !$lr && !$left_done )
   #    if ( !$rr && !$right_done )
   # If you make changes here, be sure to test both RowDiff.t
   # and RowDiff-custom.t. Look inside the later to see what
   # is custom about it.
   my $left_done  = 0;
   my $right_done = 0;
   my $done       = $self->{done};

   do {
      if ( !$lr && !$left_done ) {
         PTDEBUG && _d('Fetching row from left');
         eval { $lr = $left_sth->fetchrow_hashref(); };
         PTDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
         $left_done = !$lr || $EVAL_ERROR ? 1 : 0;
      }
      elsif ( PTDEBUG ) {
         _d('Left still has rows');
      }

      if ( !$rr && !$right_done ) {
         PTDEBUG && _d('Fetching row from right');
         eval { $rr = $right_sth->fetchrow_hashref(); };
         PTDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
         $right_done = !$rr || $EVAL_ERROR ? 1 : 0;
      }
      elsif ( PTDEBUG ) {
         _d('Right still has rows');
      }

      my $cmp;
      if ( $lr && $rr ) {
         $cmp = $self->key_cmp(%args, lr => $lr, rr => $rr);
         PTDEBUG && _d('Key comparison on left and right:', $cmp);
      }
      if ( $lr || $rr ) {
         # If the current row is the "same row" on both sides, meaning the two
         # rows have the same key, check the contents of the row to see if
         # they're the same.
         if ( $lr && $rr && defined $cmp && $cmp == 0 ) {
            PTDEBUG && _d('Left and right have the same key');
            $syncer->same_row(%args, lr => $lr, rr => $rr);
            $self->{same_row}->(%args, lr => $lr, rr => $rr)
               if $self->{same_row};
            $lr = $rr = undef; # Fetch another row from each side.
         }
         # The row in the left doesn't exist in the right.
         elsif ( !$rr || ( defined $cmp && $cmp < 0 ) ) {
            PTDEBUG && _d('Left is not in right');
            $syncer->not_in_right(%args, lr => $lr, rr => $rr);
            $self->{not_in_right}->(%args, lr => $lr, rr => $rr)
               if $self->{not_in_right};
            $lr = undef;
         }
         # Symmetric to the above.
         else {
            PTDEBUG && _d('Right is not in left');
            $syncer->not_in_left(%args, lr => $lr, rr => $rr);
            $self->{not_in_left}->(%args, lr => $lr, rr => $rr)
               if $self->{not_in_left};
            $rr = undef;
         }
      }
      $left_done = $right_done = 1 if $done && $done->(%args);
   } while ( !($left_done && $right_done) );
   PTDEBUG && _d('No more rows');
   $syncer->done_with_rows();
}

# Compare two rows to determine how they should be ordered.  NULL sorts before
# defined values in MySQL, so I consider undef "less than." Numbers are easy to
# compare.  Otherwise string comparison is tricky.  This function must match
# MySQL exactly or the merge algorithm runs off the rails, so when in doubt I
# ask MySQL to compare strings for me.  I can handle numbers and "normal" latin1
# characters without asking MySQL.  See
# http://dev.mysql.com/doc/refman/5.0/en/charset-literal.html.  $r1 and $r2 are
# row hashrefs.  $key_cols is an arrayref of the key columns to compare.  $tbl is the
# structure returned by TableParser.  The result matches Perl's cmp or <=>
# operators:
# 1 cmp 0 =>  1
# 1 cmp 1 =>  0
# 1 cmp 2 => -1
# TODO: must generate the comparator function dynamically for speed, so we don't
# have to check the type of columns constantly
sub key_cmp {
   my ( $self, %args ) = @_;
   my @required_args = qw(lr rr key_cols tbl_struct);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless exists $args{$arg};
   }
   my ($lr, $rr, $key_cols, $tbl_struct) = @args{@required_args};
   PTDEBUG && _d('Comparing keys using columns:', join(',', @$key_cols));

   # Optional callbacks.
   my $callback = $self->{key_cmp};
   my $trf      = $self->{trf};

   foreach my $col ( @$key_cols ) {
      my $l = $lr->{$col};
      my $r = $rr->{$col};
      if ( !defined $l || !defined $r ) {
         PTDEBUG && _d($col, 'is not defined in both rows');
         return defined $l ? 1 : defined $r ? -1 : 0;
      }
      else {
         if ( $tbl_struct->{is_numeric}->{$col} ) {   # Numeric column
            PTDEBUG && _d($col, 'is numeric');
            ($l, $r) = $trf->($l, $r, $tbl_struct, $col) if $trf;
            my $cmp = $l <=> $r;
            if ( $cmp ) {
               PTDEBUG && _d('Column', $col, 'differs:', $l, '!=', $r);
               $callback->($col, $l, $r) if $callback;
               return $cmp;
            }
         }
         # Do case-sensitive cmp, expecting most will be eq.  If that fails, try
         # a case-insensitive cmp if possible; otherwise ask MySQL how to sort.
         elsif ( $l ne $r ) {
            my $cmp;
            my $coll = $tbl_struct->{collation_for}->{$col};
            if ( $coll && ( $coll ne 'latin1_swedish_ci'
                           || $l =~ m/[^\040-\177]/ || $r =~ m/[^\040-\177]/) )
            {
               PTDEBUG && _d('Comparing', $col, 'via MySQL');
               $cmp = $self->db_cmp($coll, $l, $r);
            }
            else {
               PTDEBUG && _d('Comparing', $col, 'in lowercase');
               $cmp = lc $l cmp lc $r;
            }
            if ( $cmp ) {
               PTDEBUG && _d('Column', $col, 'differs:', $l, 'ne', $r);
               $callback->($col, $l, $r) if $callback;
               return $cmp;
            }
         }
      }
   }
   return 0;
}

sub db_cmp {
   my ( $self, $collation, $l, $r ) = @_;
   if ( !$self->{sth}->{$collation} ) {
      if ( !$self->{charset_for} ) {
         PTDEBUG && _d('Fetching collations from MySQL');
         my @collations = @{$self->{dbh}->selectall_arrayref(
            'SHOW COLLATION', {Slice => { collation => 1, charset => 1 }})};
         foreach my $collation ( @collations ) {
            $self->{charset_for}->{$collation->{collation}}
               = $collation->{charset};
         }
      }
      my $sql = "SELECT STRCMP(_$self->{charset_for}->{$collation}? COLLATE $collation, "
         . "_$self->{charset_for}->{$collation}? COLLATE $collation) AS res";
      PTDEBUG && _d($sql);
      $self->{sth}->{$collation} = $self->{dbh}->prepare($sql);
   }
   my $sth = $self->{sth}->{$collation};
   $sth->execute($l, $r);
   return $sth->fetchall_arrayref()->[0]->[0];
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
# End RowDiff package
# ###########################################################################
