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
# ChangeHandler package
# ###########################################################################
{
# Package: ChangeHandler
# ChangeHandler creates SQL statements for changing rows in a table.
package ChangeHandler;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

my $DUPE_KEY  = qr/Duplicate entry/;
our @ACTIONS  = qw(DELETE REPLACE INSERT UPDATE);

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   left_db   - Left database (src by default)
#   left_tbl  - Left table (src by default)
#   right_db  - Right database (dst by default)
#   right_tbl - Right table (dst by default)
#   actions   - arrayref of subroutines to call when handling a change.
#   replace   - Do UPDATE/INSERT as REPLACE.
#   queue     - Queue changes until <process_rows()> is called with a greater
#               queue level.
#   Quoter    - <Quoter> object
#
# Optional Arguments:
#   tbl_struct - Used to sort columns and detect binary columns
#   hex_blob   - HEX() BLOB columns (default yes)
#
# Returns:
#   ChangeHandler object
sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(Quoter left_db left_tbl right_db right_tbl
                        replace queue) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $q = $args{Quoter};

   my $self = {
      hex_blob     => 1,
      %args,
      left_db_tbl  => $q->quote(@args{qw(left_db left_tbl)}),
      right_db_tbl => $q->quote(@args{qw(right_db right_tbl)}),
   };

   # By default left is source and right is dest.  With bidirectional
   # syncing this can change.  See set_src().
   $self->{src_db_tbl} = $self->{left_db_tbl};
   $self->{dst_db_tbl} = $self->{right_db_tbl};

   # Init and zero changes for all actions.
   map { $self->{$_} = [] } @ACTIONS;
   $self->{changes} = { map { $_ => 0 } @ACTIONS };

   return bless $self, $class;
}

# Sub: fetch_back
#   Set the fetch-back dbh.  If I'm supposed to fetch-back, that means I have
#   to get the full row from the database.  For example, someone might call
#   me like so: $me->change('UPDATE', { a => 1 })  But 'a' is only the primary
#   key. I now need to select that row and make an UPDATE statement with all
#   of its columns.
#
# Parameters:
#   $dbh - dbh to use for fetching-back values
sub fetch_back {
   my ( $self, $dbh ) = @_;
   $self->{fetch_back} = $dbh;
   PTDEBUG && _d('Set fetch back dbh', $dbh);
   return;
}

# Sub: set_src
#   Set which side of left-right pair is the source.
#   For bidirectional syncing both tables are src and dst.  Internally,
#   we refer to the tables generically as the left and right.  Either
#   one can be src or dst, as set by this sub when called by the caller.
#   Other subs don't know to which table src or dst point.  They just
#   fetchback from src and change dst.  If the optional $dbh arg is
#   given, fetch_back() is set with it, too.
#
# Parameters:
#   $src - Hashref with source host information
#   $dbh - Set <fetch_back()> with this dbh if given
sub set_src {
   my ( $self, $src, $dbh ) = @_;
   die "I need a src argument" unless $src;
   if ( lc $src eq 'left' ) {
      $self->{src_db_tbl} = $self->{left_db_tbl};
      $self->{dst_db_tbl} = $self->{right_db_tbl};
   }
   elsif ( lc $src eq 'right' ) {
      $self->{src_db_tbl} = $self->{right_db_tbl};
      $self->{dst_db_tbl} = $self->{left_db_tbl}; 
   }
   else {
      die "src argument must be either 'left' or 'right'"
   }
   PTDEBUG && _d('Set src to', $src);
   $self->fetch_back($dbh) if $dbh;
   return;
}

# Sub: src
#   Return current source db.tbl (could be left or right table).
#
# Returns:
#   Source database-qualified table name
sub src {
   my ( $self ) = @_;
   return $self->{src_db_tbl};
}

# Sub: dst
#   Return current destination db.tbl (could be left or right table).
#
# Returns:
#   Destination database-qualified table name
sub dst {
   my ( $self ) = @_;
   return $self->{dst_db_tbl};
}

# Sub: _take_action
#   Call the user-provied actions.  Actions are passed an action statement
#   and an optional dbh.  This sub is not called directly; it's called
#   by <change()> or <process_rows()>.
#
# Parameters:
#   sql - A SQL statement
#   dbh - optional dbh passed to the action callback
sub _take_action {
   my ( $self, $sql, $dbh ) = @_;
   PTDEBUG && _d('Calling subroutines on', $dbh, $sql);
   foreach my $action ( @{$self->{actions}} ) {
      $action->($sql, $dbh);
   }
   return;
}

# Sub: change
#   Make an action SQL statment for the given parameters if not queueing.
#   This sub calls <_take_action()>, passing the action statement and
#   optional dbh.  If queueing, the parameters are saved and the same work
#   is done in <process_rows()>.  Queueing does not work with bidirectional
#   syncs.
#
# Parameters:
#   action - One of @ACTIONS
#   row    - Hashref of row data
#   cols   - Arrayref of column names
#   dbh    - Optional dbh passed to <_take_action()>
sub change {
   my ( $self, $action, $row, $cols, $dbh ) = @_;
   PTDEBUG && _d($dbh, $action, 'where', $self->make_where_clause($row, $cols));

   # Undef action means don't do anything.  This allows deeply
   # nested callers to avoid/skip a change without dying.
   return unless $action;

   $self->{changes}->{
      $self->{replace} && $action ne 'DELETE' ? 'REPLACE' : $action
   }++;
   if ( $self->{queue} ) {
      $self->__queue($action, $row, $cols, $dbh);
   }
   else {
      eval {
         my $func = "make_$action";
         $self->_take_action($self->$func($row, $cols), $dbh);
      };
      if ( $EVAL_ERROR =~ m/$DUPE_KEY/ ) {
         PTDEBUG && _d('Duplicate key violation; will queue and rewrite');
         $self->{queue}++;
         $self->{replace} = 1;
         $self->__queue($action, $row, $cols, $dbh);
      }
      elsif ( $EVAL_ERROR ) {
         die $EVAL_ERROR;
      }
   }
   return;
}

# Sub: __queue
#   Queue an action for later execution.  This sub is called by <change()>
#   <process_rows()> to defer action.
#
# Parameters:
#   action - One of @ACTIONS
#   row    - Hashref of row data
#   cols   - Arrayref of column names
#   dbh    - Optional dbh passed to <_take_action()>
sub __queue {
   my ( $self, $action, $row, $cols, $dbh ) = @_;
   PTDEBUG && _d('Queueing change for later');
   if ( $self->{replace} ) {
      $action = $action eq 'DELETE' ? $action : 'REPLACE';
   }
   push @{$self->{$action}}, [ $row, $cols, $dbh ];
}

# Sub: process_rows
#   Make changes to rows created/queued earlier.
#   If called with 1, will process rows that have been deferred from instant
#   processing.  If no arg, will process all rows.
#
# Parameters:
#   $queue_level - Queue level caller is in
#   $trace_msg   - Optional string to append to each SQL statement for
#                  tracing them in binary logs.
sub process_rows {
   my ( $self, $queue_level, $trace_msg ) = @_;
   my $error_count = 0;
   TRY: {
      if ( $queue_level && $queue_level < $self->{queue} ) { # see redo below!
         PTDEBUG && _d('Not processing now', $queue_level, '<', $self->{queue});
         return;
      }
      PTDEBUG && _d('Processing rows:');
      my ($row, $cur_act);
      eval {
         foreach my $action ( @ACTIONS ) {
            my $func = "make_$action";
            my $rows = $self->{$action};
            PTDEBUG && _d(scalar(@$rows), 'to', $action);
            $cur_act = $action;
            while ( @$rows ) {
               # Each row is an arrayref like:
               # [
               #   { col1 => val1, colN => ... },
               #   [ col1, colN, ... ],
               #   dbh,  # optional
               # ]
               $row    = shift @$rows;
               my $sql = $self->$func(@$row);
               $sql   .= " /*percona-toolkit $trace_msg*/" if $trace_msg;
               $self->_take_action($sql, $row->[2]);
            }
         }
         $error_count = 0;
      };
      if ( !$error_count++ && $EVAL_ERROR =~ m/$DUPE_KEY/ ) {
         PTDEBUG && _d('Duplicate key violation; re-queueing and rewriting');
         $self->{queue}++; # Defer rows to the very end
         $self->{replace} = 1;
         $self->__queue($cur_act, @$row);
         redo TRY;
      }
      elsif ( $EVAL_ERROR ) {
         die $EVAL_ERROR;
      }
   }
}

# Sub: make_DELETE
#   Make a DELETE statement.  DELETE never needs to be fetched back.
#
# Parameters:
#   $row  - Hashref with row values
#   $cols - Arrayref with column names
#
# Returns:
#   A DELETE statement for the given row and columns
sub make_DELETE {
   my ( $self, $row, $cols ) = @_;
   PTDEBUG && _d('Make DELETE');
   return "DELETE FROM $self->{dst_db_tbl} WHERE "
      . $self->make_where_clause($row, $cols)
      . ' LIMIT 1';
}

# Sub: make_UPDATE
#   Make an UPDATE statement.
#
# Parameters:
#   $row  - Hashref with row values
#   $cols - Arrayref with column names
#
# Returns:
#   An UPDATE statement for the given row and columns
sub make_UPDATE {
   my ( $self, $row, $cols ) = @_;
   PTDEBUG && _d('Make UPDATE');
   if ( $self->{replace} ) {
      return $self->make_row('REPLACE', $row, $cols);
   }
   my %in_where = map { $_ => 1 } @$cols;
   my $where = $self->make_where_clause($row, $cols);
   my @cols;
   if ( my $dbh = $self->{fetch_back} ) {
      my $sql = $self->make_fetch_back_query($where);
      PTDEBUG && _d('Fetching data on dbh', $dbh, 'for UPDATE:', $sql);
      my $res = $dbh->selectrow_hashref($sql);
      @{$row}{keys %$res} = values %$res;
      @cols = $self->sort_cols($res);
   }
   else {
      @cols = $self->sort_cols($row);
   }
   my $types = $self->{tbl_struct}->{type_for};
   return "UPDATE $self->{dst_db_tbl} SET "
      . join(', ', map {
            my $is_char  = ($types->{$_} || '') =~ m/char|text|enum/i;
            my $is_float = ($types->{$_} || '') =~ m/float|double/i;
            $self->{Quoter}->quote($_)
            . '='
            .  $self->{Quoter}->quote_val(
                  $row->{$_},
                  is_char  => $is_char,
                  is_float => $is_float,
            );
         } grep { !$in_where{$_} } @cols)
      . " WHERE $where LIMIT 1";
}

# Sub: make_INSERT
#   Make an INSERT statement.  This sub is stub for <make_row()> which
#   does the real work.
#
# Parameters:
#   $row  - Hashref with row values
#   $cols - Arrayref with column names
#
# Returns:
#   An INSERT statement for the given row and columns
sub make_INSERT {
   my ( $self, $row, $cols ) = @_;
   PTDEBUG && _d('Make INSERT');
   if ( $self->{replace} ) {
      return $self->make_row('REPLACE', $row, $cols);
   }
   return $self->make_row('INSERT', $row, $cols);
}

# Sub: make_REPLACE
#   Make a REPLACE statement.  This sub is a stub for <make_row()> which
#   does the real work.
#
# Parameters:
#   $row  - Hashref with row values
#   $cols - Arrayref with column names
#
# Returns:
#   A REPLACE statement for the given row and columns
sub make_REPLACE {
   my ( $self, $row, $cols ) = @_;
   PTDEBUG && _d('Make REPLACE');
   return $self->make_row('REPLACE', $row, $cols);
}

# Sub: make_row
#   Make an INSERT or REPLACE statement.  Values from $row are quoted
#   with <Quoter::quote_val()>.
#
# Parameters:
#   $verb - "INSERT" or "REPLACE"
#   $row  - Hashref with row values
#   $cols - Arrayref with column names
#
# Returns:
#   A SQL statement
sub make_row {
   my ( $self, $verb, $row, $cols ) = @_;
   my @cols; 
   if ( my $dbh = $self->{fetch_back} ) {
      my $where = $self->make_where_clause($row, $cols);
      my $sql   = $self->make_fetch_back_query($where);
      PTDEBUG && _d('Fetching data on dbh', $dbh, 'for', $verb, ':', $sql);
      my $res = $dbh->selectrow_hashref($sql);
      @{$row}{keys %$res} = values %$res;
      @cols = $self->sort_cols($res);
   }
   else {
      @cols = $self->sort_cols($row);
   }
   my $q     = $self->{Quoter};
   my $type_for = $self->{tbl_struct}->{type_for};

   return "$verb INTO $self->{dst_db_tbl}("
      . join(', ', map { $q->quote($_) } @cols)
      . ') VALUES ('
      . join(', ',
            map {
               my $is_char  = ($type_for->{$_} || '') =~ m/char|text/i;
               my $is_float = ($type_for->{$_} || '') =~ m/float|double/i;
               $q->quote_val(
                     $row->{$_},
                     is_char  => $is_char,
                     is_float => $is_float,
               )
            } @cols)
      . ')';

}

# Sub: make_where_clause
#   Make a WHERE clause.  Values are quoted with <Quoter::quote_val()>.
#
# Parameters:
#   $row  - Hashref with row values
#   $cols - Arrayref with column names
#
# Returns:
#   A WHERE clause without the word "WHERE"
sub make_where_clause {
   my ( $self, $row, $cols ) = @_;
   my @clauses = map {
      my $val = $row->{$_};
      my $sep = defined $val ? '=' : ' IS ';
      my $is_char  = ($self->{tbl_struct}->{type_for}->{$_} || '') =~ m/char|text/i;
      my $is_float = ($self->{tbl_struct}->{type_for}->{$_} || '') =~ m/float|double/i;
      $self->{Quoter}->quote($_) . $sep . $self->{Quoter}->quote_val($val,
                                              is_char  => $is_char,
                                              is_float => $is_float);
   } @$cols;
   return join(' AND ', @clauses);
}


# Sub: get_changes
#   Get a summary of changes made.
#
# Returns:
#   Hash of changes where the keys are actions like "DELETE" and the values
#   are how many of the action were made
sub get_changes {
   my ( $self ) = @_;
   return %{$self->{changes}};
}


# Sub: sort_cols
#   Sort a row's columns based on their real order in the table.
#   This requires that the optional tbl_struct arg was passed to <new()>.
#   If not, the rows are sorted alphabetically.
#
# Parameters:
#   $row - Hashref with row values
#
# Returns:
#   Array of column names
sub sort_cols {
   my ( $self, $row ) = @_;
   my @cols;
   if ( $self->{tbl_struct} ) { 
      my $pos = $self->{tbl_struct}->{col_posn};
      my @not_in_tbl;
      @cols = sort {
            $pos->{$a} <=> $pos->{$b}
         }
         grep {
            if ( !defined $pos->{$_} ) {
               push @not_in_tbl, $_;
               0;
            }
            else {
               1;
            }
         }
         sort keys %$row;
      push @cols, @not_in_tbl if @not_in_tbl;
   }
   else {
      @cols = sort keys %$row;
   }
   return @cols;
}

# Sub: make_fetch_back_query
#   Make a SELECT statement to fetch-back values.
#   This requires that the optional tbl_struct arg was passed to <new()>.
#
# Parameters:
#   $where - Optional WHERE clause without the word "WHERE"
#
# Returns:
#   A SELECT statement
sub make_fetch_back_query {
   my ( $self, $where ) = @_;
   die "I need a where argument" unless $where;
   my $cols       = '*';
   my $tbl_struct = $self->{tbl_struct};
   if ( $tbl_struct ) {
      $cols = join(', ',
         map {
            my $col = $_;
            if (    $self->{hex_blob}
                 && $tbl_struct->{type_for}->{$col} =~ m/b(?:lob|inary)/ ) {
               # Here we cast to binary, as otherwise, since text columns are
               # space padded, MySQL would compare ' ' and '' to be the same.
               # See https://bugs.launchpad.net/percona-toolkit/+bug/930693
               $col = "IF(BINARY(`$col`)='', '', CONCAT('0x', HEX(`$col`))) AS `$col`";
            }
            else {
               $col = "`$col`";
            }
            $col;
         } @{ $tbl_struct->{cols} }
      );

      if ( !$cols ) {
         # This shouldn't happen in the real world.
         PTDEBUG && _d('Failed to make explicit columns list from tbl struct');
         $cols = '*';
      }
   }
   return "SELECT $cols FROM $self->{src_db_tbl} WHERE $where LIMIT 1";
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
# End ChangeHandler package
# ###########################################################################
