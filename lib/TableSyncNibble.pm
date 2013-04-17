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
# TableSyncNibble package
# ###########################################################################
{
# Package: TableSyncNibble
# TableSyncNibble is a table sync algo that uses <TableNibbler>.
# This package implements a moderately complex sync algorithm:
# * Prepare to nibble the table (see TableNibbler.pm)
# * Fetch the nibble'th next row (say the 500th) from the current row
# * Checksum from the current row to the nibble'th as a chunk
# * If nibble differs, make a note to checksum the rows in the nibble (state 1)
# * Checksum them (state 2)
# * If a row differs, it must be synced
# See TableSyncStream for the TableSync interface this conforms to.
package TableSyncNibble;

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
   foreach my $arg ( qw(TableNibbler TableChunker TableParser Quoter) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub name {
   return 'Nibble';
}

# Returns a hash (true) with a chunk_index that can be used to sync
# the given tbl_struct.  Else, returns nothing (false) if the table
# cannot be synced.  Arguments:
#   * tbl_struct    Return value of TableParser::parse()
#   * chunk_index   (optional) Index to use for chunking
# If chunk_index is given, then it is required so the return value will
# only be true if it's the best possible index.  If it's not given, then
# the best possible index is returned.  The return value should be passed
# back to prepare_to_sync().  -- nibble_index is the same as chunk_index:
# both are used to select multiple rows at once in state 0.
sub can_sync {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(tbl_struct) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   # If there's an index, TableNibbler::generate_asc_stmt() will use it,
   # so it is an indication that the nibble algorithm will work.
   my $nibble_index = $self->{TableParser}->find_best_index($args{tbl_struct});
   if ( $nibble_index ) {
      PTDEBUG && _d('Best nibble index:', Dumper($nibble_index));
      if ( !$args{tbl_struct}->{keys}->{$nibble_index}->{is_unique} ) {
         PTDEBUG && _d('Best nibble index is not unique');
         return;
      }
      if ( $args{chunk_index} && $args{chunk_index} ne $nibble_index ) {
         PTDEBUG && _d('Best nibble index is not requested index',
            $args{chunk_index});
         return;
      }
   }
   else {
      PTDEBUG && _d('No best nibble index returned');
      return;
   }

   # MySQL may choose to use no index for small tables because it's faster.
   # However, this will cause __get_boundaries() to die with a "Cannot nibble
   # table" error.  So we check if the table is small and if it is then we
   # let MySQL do whatever it wants and let ORDER BY keep us safe.
   my $small_table = 0;
   if ( $args{src} && $args{src}->{dbh} ) {
      my $dbh = $args{src}->{dbh};
      my $db  = $args{src}->{db};
      my $tbl = $args{src}->{tbl};
      my $table_status;
      eval {
         my $sql = "SHOW TABLE STATUS FROM `$db` LIKE "
                 . $self->{Quoter}->literal_like($tbl);
         PTDEBUG && _d($sql);
         $table_status = $dbh->selectrow_hashref($sql);
      };
      PTDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
      if ( $table_status ) {
         my $n_rows   = defined $table_status->{Rows} ? $table_status->{Rows}
                      : defined $table_status->{rows} ? $table_status->{rows}
                      : undef;
         $small_table = 1 if defined $n_rows && $n_rows <= 100;
      }
   }
   PTDEBUG && _d('Small table:', $small_table);

   PTDEBUG && _d('Can nibble using index', $nibble_index);
   return (
      1,
      chunk_index => $nibble_index,
      key_cols    => $args{tbl_struct}->{keys}->{$nibble_index}->{cols},
      small_table => $small_table,
   );
}

sub prepare_to_sync {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct chunk_index key_cols chunk_size
                          crc_col ChangeHandler);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   $self->{dbh}             = $args{dbh};
   $self->{tbl_struct}      = $args{tbl_struct};
   $self->{crc_col}         = $args{crc_col};
   $self->{index_hint}      = $args{index_hint};
   $self->{key_cols}        = $args{key_cols};
   ($self->{chunk_size})    = $self->{TableChunker}->size_to_rows(%args);
   $self->{buffer_in_mysql} = $args{buffer_in_mysql};
   $self->{small_table}     = $args{small_table};
   $self->{ChangeHandler}   = $args{ChangeHandler};

   $self->{ChangeHandler}->fetch_back($args{dbh});

   # Make sure our chunk col is in the list of comparison columns
   # used by TableChecksum::make_row_checksum() to create $row_sql.
   # Normally that sub removes dupes, but the code to make boundary
   # sql does not, so we do it here.
   my %seen;
   my @ucols = grep { !$seen{$_}++ } @{$args{cols}}, @{$args{key_cols}};
   $args{cols} = \@ucols;

   $self->{sel_stmt} = $self->{TableNibbler}->generate_asc_stmt(
      %args,
      index    => $args{chunk_index}, # expects an index arg, not chunk_index
      asc_only => 1,
   );

   $self->{nibble}            = 0;
   $self->{cached_row}        = undef;
   $self->{cached_nibble}     = undef;
   $self->{cached_boundaries} = undef;
   $self->{state}             = 0;

   return;
}

sub uses_checksum {
   return 1;
}

sub set_checksum_queries {
   my ( $self, $nibble_sql, $row_sql ) = @_;
   die "I need a nibble_sql argument" unless $nibble_sql;
   die "I need a row_sql argument" unless $row_sql;
   $self->{nibble_sql} = $nibble_sql;
   $self->{row_sql} = $row_sql;
   return;
}

sub prepare_sync_cycle {
   my ( $self, $host ) = @_;
   my $sql = q{SET @crc := '', @cnt := 0};
   PTDEBUG && _d($sql);
   $host->{dbh}->do($sql);
   return;
}

# Returns a SELECT statement that either gets a nibble of rows (state=0) or,
# if the last nibble was bad (state=1 or 2), gets the rows in the nibble.
# This way we can sync part of the table before moving on to the next part.
# Required args: database, table
# Optional args: where
sub get_sql {
   my ( $self, %args ) = @_;
   if ( $self->{state} ) {
      # Selects the individual rows so that they can be compared.
      my $q = $self->{Quoter};
      return 'SELECT /*rows in nibble*/ '
         . ($self->{buffer_in_mysql} ? 'SQL_BUFFER_RESULT ' : '')
         . $self->{row_sql} . " AS $self->{crc_col}"
         . ' FROM ' . $q->quote(@args{qw(database table)})
         . ' ' . ($self->{index_hint} ? $self->{index_hint} : '')
         . ' WHERE (' . $self->__get_boundaries(%args) . ')'
         . ($args{where} ? " AND ($args{where})" : '')
         . ' ORDER BY ' . join(', ', map {$q->quote($_) } @{$self->key_cols()});
   }
   else {
      # Selects the rows as a nibble (aka a chunk).
      my $where = $self->__get_boundaries(%args);
      return $self->{TableChunker}->inject_chunks(
         database   => $args{database},
         table      => $args{table},
         chunks     => [ $where ],
         chunk_num  => 0,
         query      => $self->{nibble_sql},
         index_hint => $self->{index_hint},
         where      => [ $args{where} ],
      );
   }
}

# Returns a WHERE clause for selecting rows in a nibble relative to lower
# and upper boundary rows.  Initially neither boundary is defined, so we
# get the first upper boundary row and return a clause like:
#   WHERE rows < upper_boundary_row1
# This selects all "lowest" rows: those before/below the first nibble
# boundary.  The upper boundary row is saved (as cached_row) so that on the
# next call it becomes the lower boundary and we get the next upper boundary,
# resulting in a clause like:
#   WHERE rows > cached_row && col < upper_boundary_row2
# This process repeats for subsequent calls. Assuming that the source and
# destination tables have different data, executing the same query against
# them might give back a different boundary row, which is not what we want,
# so each boundary needs to be cached until the nibble increases.
sub __get_boundaries {
   my ( $self, %args ) = @_;
   my $q = $self->{Quoter};
   my $s = $self->{sel_stmt};

   my $lb;   # Lower boundary part of WHERE
   my $ub;   # Upper boundary part of WHERE
   my $row;  # Next upper boundary row or cached_row

   if ( $self->{cached_boundaries} ) {
      PTDEBUG && _d('Using cached boundaries');
      return $self->{cached_boundaries};
   }

   if ( $self->{cached_row} && $self->{cached_nibble} == $self->{nibble} ) {
      # If there's a cached (last) row and the nibble number hasn't increased
      # then a differing row was found in this nibble.  We re-use its
      # boundaries so that instead of advancing to the next nibble we'll look
      # at the row in this nibble (get_sql() will return its SELECT
      # /*rows in nibble*/ query).
      PTDEBUG && _d('Using cached row for boundaries');
      $row = $self->{cached_row};
   }
   else {
      PTDEBUG && _d('Getting next upper boundary row');
      my $sql;
      ($sql, $lb) = $self->__make_boundary_sql(%args);  # $lb from outer scope!

      # Check that $sql will use the index chosen earlier in new().
      # Only do this for the first nibble.  I assume this will be safe
      # enough since the WHERE should use the same columns.
      if ( $self->{nibble} == 0 && !$self->{small_table} ) {
         my $explain_index = $self->__get_explain_index($sql);
         if ( lc($explain_index || '') ne lc($s->{index}) ) {
            die 'Cannot nibble table '.$q->quote($args{database}, $args{table})
               . " because MySQL chose "
               . ($explain_index ? "the `$explain_index`" : 'no') . ' index'
               . " instead of the `$s->{index}` index";
         }
      }

      $row = $self->{dbh}->selectrow_hashref($sql);
      PTDEBUG && _d($row ? 'Got a row' : "Didn't get a row");
   }

   if ( $row ) {
      # Add the row to the WHERE clause as the upper boundary.  As such,
      # the table rows should be <= to this boundary.  (Conversely, for
      # any lower boundary the table rows should be > the lower boundary.)
      my $i = 0;
      $ub   = $s->{boundaries}->{'<='};
      $ub   =~ s/\?/$q->quote_val($row->{$s->{scols}->[$i++]})/eg;
   }
   else {
      # This usually happens at the end of the table, after we've nibbled
      # all the rows.
      PTDEBUG && _d('No upper boundary');
      $ub = '1=1';
   }

   # If $lb is defined, then this is the 2nd or subsequent nibble and
   # $ub should be the previous boundary.  Else, this is the first nibble.
   # Do not append option where arg here; it is added by the caller.
   my $where = $lb ? "($lb AND $ub)" : $ub;

   $self->{cached_row}        = $row;
   $self->{cached_nibble}     = $self->{nibble};
   $self->{cached_boundaries} = $where;

   PTDEBUG && _d('WHERE clause:', $where);
   return $where;
}

# Returns a SELECT statement for the next upper boundary row and the
# lower boundary part of WHERE if this is the 2nd or subsequent nibble.
# (The first nibble doesn't have a lower boundary.)  The returned SELECT
# is largely responsible for nibbling the table because if the boundaries
# are off then the nibble may not advance properly and we'll get stuck
# in an infinite loop (issue 96).
sub __make_boundary_sql {
   my ( $self, %args ) = @_;
   my $lb;
   my $q   = $self->{Quoter};
   my $s   = $self->{sel_stmt};
   my $sql = "SELECT /*nibble boundary $self->{nibble}*/ "
      . join(',', map { $q->quote($_) } @{$s->{cols}})
      . " FROM " . $q->quote($args{database}, $args{table})
      . ' ' . ($self->{index_hint} || '')
      . ($args{where} ? " WHERE ($args{where})" : "");

   if ( $self->{nibble} ) {
      # The lower boundaries of the nibble must be defined, based on the last
      # remembered row.
      my $tmp = $self->{cached_row};
      my $i   = 0;
      $lb     = $s->{boundaries}->{'>'};
      $lb     =~ s/\?/$q->quote_val($tmp->{$s->{scols}->[$i++]})/eg;
      $sql   .= $args{where} ? " AND $lb" : " WHERE $lb";
   }
   $sql .= " ORDER BY " . join(',', map { $q->quote($_) } @{$self->{key_cols}})
         . ' LIMIT ' . ($self->{chunk_size} - 1) . ', 1';
   PTDEBUG && _d('Lower boundary:', $lb);
   PTDEBUG && _d('Next boundary sql:', $sql);
   return $sql, $lb;
}

# Returns just the index value from EXPLAIN for the given query (sql).
sub __get_explain_index {
   my ( $self, $sql ) = @_;
   return unless $sql;
   my $explain;
   eval {
      $explain = $self->{dbh}->selectall_arrayref("EXPLAIN $sql",{Slice => {}});
   };
   if ( $EVAL_ERROR ) {
      PTDEBUG && _d($EVAL_ERROR);
      return;
   }
   PTDEBUG && _d('EXPLAIN key:', $explain->[0]->{key}); 
   return $explain->[0]->{key};
}

sub same_row {
   my ( $self, %args ) = @_;
   my ($lr, $rr) = @args{qw(lr rr)};
   if ( $self->{state} ) {
      if ( $lr->{$self->{crc_col}} ne $rr->{$self->{crc_col}} ) {
         $self->{ChangeHandler}->change('UPDATE', $lr, $self->key_cols());
      }
   }
   elsif ( $lr->{cnt} != $rr->{cnt} || $lr->{crc} ne $rr->{crc} ) {
      PTDEBUG && _d('Rows:', Dumper($lr, $rr));
      PTDEBUG && _d('Will examine this nibble before moving to next');
      $self->{state} = 1; # Must examine this nibble row-by-row
   }
}

# This (and not_in_left) should NEVER be called in state 0.  If there are
# missing rows in state 0 in one of the tables, the CRC will be all 0's and the
# cnt will be 0, but the result set should still come back.
sub not_in_right {
   my ( $self, %args ) = @_;
   die "Called not_in_right in state 0" unless $self->{state};
   $self->{ChangeHandler}->change('INSERT', $args{lr}, $self->key_cols());
}

sub not_in_left {
   my ( $self, %args ) = @_;
   die "Called not_in_left in state 0" unless $self->{state};
   $self->{ChangeHandler}->change('DELETE', $args{rr}, $self->key_cols());
}

sub done_with_rows {
   my ( $self ) = @_;
   if ( $self->{state} == 1 ) {
      $self->{state} = 2;
      PTDEBUG && _d('Setting state =', $self->{state});
   }
   else {
      $self->{state} = 0;
      $self->{nibble}++;
      delete $self->{cached_boundaries};
      PTDEBUG && _d('Setting state =', $self->{state},
         ', nibble =', $self->{nibble});
   }
}

sub done {
   my ( $self ) = @_;
   PTDEBUG && _d('Done with nibble', $self->{nibble});
   PTDEBUG && $self->{state} && _d('Nibble differs; must examine rows');
   return $self->{state} == 0 && $self->{nibble} && !$self->{cached_row};
}

sub pending_changes {
   my ( $self ) = @_;
   if ( $self->{state} ) {
      PTDEBUG && _d('There are pending changes');
      return 1;
   }
   else {
      PTDEBUG && _d('No pending changes');
      return 0;
   }
}

sub key_cols {
   my ( $self ) = @_;
   my @cols;
   if ( $self->{state} == 0 ) {
      @cols = qw(chunk_num);
   }
   else {
      @cols = @{$self->{key_cols}};
   }
   PTDEBUG && _d('State', $self->{state},',', 'key cols', join(', ', @cols));
   return \@cols;
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
# End TableSyncNibble package
# ###########################################################################
