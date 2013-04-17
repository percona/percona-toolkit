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
# TableSyncChunk package
# ###########################################################################
{
# Package: TableSyncChunk
# TableSyncChunk is a table sync algo that uses discrete chunks.
# This package implements a simple sync algorithm:
# * Chunk the table (see TableChunker.pm)
# * Checksum each chunk (state 0)
# * If a chunk differs, make a note to checksum the rows in the chunk (state 1)
# * Checksum them (state 2)
# * If a row differs, it must be synced
# See TableSyncStream for the TableSync interface this conforms to.
package TableSyncChunk;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# Required args:
#   * TableChunker   obj: common module
#   * Quoter         obj: common module
# Optional args:
#   * same_row       coderef: These three callbacks allow the caller to
#   * not_in_left    coderef: override the default behavior of the respective
#   * not_in_right   coderef: subs.  Used for bidirectional syncs.
sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(TableChunker Quoter) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub name {
   return 'Chunk';
}

sub set_callback {
   my ( $self, $callback, $code ) = @_;
   $self->{$callback} = $code;
   return;
}

# Returns a hash (true) with a chunk_col and chunk_index that can be used
# to sync the given tbl_struct.  Else, returns nothing (false) if the table
# cannot be synced.  Arguments:
#   * tbl_struct    Return value of TableParser::parse()
#   * chunk_col     (optional) Column name to chunk on
#   * chunk_index   (optional) Index to use for chunking
# If either chunk_col or chunk_index are given, then they are required so
# the return value will only be true if they're among the possible chunkable
# columns.  If neither is given, then the first (best) chunkable col and index
# are returned.  The return value should be passed back to prepare_to_sync().
sub can_sync {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(tbl_struct) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   # Find all possible chunkable cols/indexes.  If Chunker can handle it OK
   # but *not* with exact chunk sizes, it means it's using only the first
   # column of a multi-column index, which could be really bad.  It's better
   # to use Nibble for these, because at least it can reliably select a chunk
   # of rows of the desired size.
   my ($exact, @chunkable_cols) = $self->{TableChunker}->find_chunk_columns(
      %args,
      exact => 1,
   );
   return unless $exact;

   # Check if the requested chunk col and/or index are among the possible
   # columns found above.
   my $colno;
   if ( $args{chunk_col} || $args{chunk_index} ) {
      PTDEBUG && _d('Checking requested col', $args{chunk_col},
         'and/or index', $args{chunk_index});
      for my $i ( 0..$#chunkable_cols ) {
         if ( $args{chunk_col} ) {
            next unless $chunkable_cols[$i]->{column} eq $args{chunk_col};
         }
         if ( $args{chunk_index} ) {
            next unless $chunkable_cols[$i]->{index} eq $args{chunk_index};
         }
         $colno = $i;
         last;
      }

      if ( !$colno ) {
         PTDEBUG && _d('Cannot chunk on column', $args{chunk_col},
            'and/or using index', $args{chunk_index});
         return;
      }
   }
   else {
      $colno = 0;  # First, best chunkable column/index.
   }

   PTDEBUG && _d('Can chunk on column', $chunkable_cols[$colno]->{column},
      'using index', $chunkable_cols[$colno]->{index});
   return (
      1,
      chunk_col   => $chunkable_cols[$colno]->{column},
      chunk_index => $chunkable_cols[$colno]->{index},
   ),
}

sub prepare_to_sync {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct cols chunk_col
                          chunk_size crc_col ChangeHandler);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $chunker  = $self->{TableChunker};

   $self->{chunk_col}       = $args{chunk_col};
   $self->{crc_col}         = $args{crc_col};
   $self->{index_hint}      = $args{index_hint};
   $self->{buffer_in_mysql} = $args{buffer_in_mysql};
   $self->{ChangeHandler}   = $args{ChangeHandler};

   $self->{ChangeHandler}->fetch_back($args{dbh});

   # Make sure our chunk col is in the list of comparison columns
   # used by TableChecksum::make_row_checksum() to create $row_sql.
   push @{$args{cols}}, $args{chunk_col};

   my @chunks;
   my %range_params = $chunker->get_range_statistics(%args);
   if ( !grep { !defined $range_params{$_} } qw(min max rows_in_range) ) {
      ($args{chunk_size}) = $chunker->size_to_rows(%args);
      @chunks = $chunker->calculate_chunks(%args, %range_params);
   }
   else {
      PTDEBUG && _d('No range statistics; using single chunk 1=1');
      @chunks = '1=1';
   }

   $self->{chunks}    = \@chunks;
   $self->{chunk_num} = 0;
   $self->{state}     = 0;

   return;
}

sub uses_checksum {
   return 1;
}

sub set_checksum_queries {
   my ( $self, $chunk_sql, $row_sql ) = @_;
   die "I need a chunk_sql argument" unless $chunk_sql;
   die "I need a row_sql argument" unless $row_sql;
   $self->{chunk_sql} = $chunk_sql;
   $self->{row_sql}   = $row_sql;
   return;
}

sub prepare_sync_cycle {
   my ( $self, $host ) = @_;
   my $sql = q{SET @crc := '', @cnt := 0};
   PTDEBUG && _d($sql);
   $host->{dbh}->do($sql);
   return;
}

# Depth-first: if there are any bad chunks, return SQL to inspect their rows
# individually.  Otherwise get the next chunk.  This way we can sync part of the
# table before moving on to the next part.
sub get_sql {
   my ( $self, %args ) = @_;
   if ( $self->{state} ) {  # select rows in a chunk
      my $q = $self->{Quoter};
      return 'SELECT /*rows in chunk*/ '
         . ($self->{buffer_in_mysql} ? 'SQL_BUFFER_RESULT ' : '')
         . $self->{row_sql} . " AS $self->{crc_col}"
         . ' FROM ' . $self->{Quoter}->quote(@args{qw(database table)})
         . ' '. ($self->{index_hint} || '')
         . ' WHERE (' . $self->{chunks}->[$self->{chunk_num}] . ')'
         . ($args{where} ? " AND ($args{where})" : '')
         . ' ORDER BY ' . join(', ', map {$q->quote($_) } @{$self->key_cols()});
   }
   else {  # select a chunk of rows
      return $self->{TableChunker}->inject_chunks(
         database   => $args{database},
         table      => $args{table},
         chunks     => $self->{chunks},
         chunk_num  => $self->{chunk_num},
         query      => $self->{chunk_sql},
         index_hint => $self->{index_hint},
         where      => [ $args{where} ],
      );
   }
}

sub same_row {
   my ( $self, %args ) = @_;
   my ($lr, $rr) = @args{qw(lr rr)};

   if ( $self->{state} ) {  # checksumming rows
      if ( $lr->{$self->{crc_col}} ne $rr->{$self->{crc_col}} ) {
         my $action   = 'UPDATE';
         my $auth_row = $lr;
         my $change_dbh;

         # Give callback a chance to determine how to handle this difference.
         if ( $self->{same_row} ) {
            ($action, $auth_row, $change_dbh) = $self->{same_row}->(%args);
         }

         $self->{ChangeHandler}->change(
            $action,            # Execute the action
            $auth_row,          # with these row values
            $self->key_cols(),  # identified by these key cols
            $change_dbh,        # on this dbh
         );
      }
   }
   elsif ( $lr->{cnt} != $rr->{cnt} || $lr->{crc} ne $rr->{crc} ) {
      # checksumming a chunk of rows
      PTDEBUG && _d('Rows:', Dumper($lr, $rr));
      PTDEBUG && _d('Will examine this chunk before moving to next');
      $self->{state} = 1; # Must examine this chunk row-by-row
   }
}

# This (and not_in_left) should NEVER be called in state 0.  If there are
# missing rows in state 0 in one of the tables, the CRC will be all 0's and the
# cnt will be 0, but the result set should still come back.
sub not_in_right {
   my ( $self, %args ) = @_;
   die "Called not_in_right in state 0" unless $self->{state};

   my $action   = 'INSERT';
   my $auth_row = $args{lr};
   my $change_dbh;

   # Give callback a chance to determine how to handle this difference.
   if ( $self->{not_in_right} ) {
      ($action, $auth_row, $change_dbh) = $self->{not_in_right}->(%args);
   }

   $self->{ChangeHandler}->change(
      $action,            # Execute the action
      $auth_row,          # with these row values
      $self->key_cols(),  # identified by these key cols
      $change_dbh,        # on this dbh
   );
   return;
}

sub not_in_left {
   my ( $self, %args ) = @_;
   die "Called not_in_left in state 0" unless $self->{state};

   my $action   = 'DELETE';
   my $auth_row = $args{rr};
   my $change_dbh;

   # Give callback a chance to determine how to handle this difference.
   if ( $self->{not_in_left} ) {
      ($action, $auth_row, $change_dbh) = $self->{not_in_left}->(%args);
   }

   $self->{ChangeHandler}->change(
      $action,            # Execute the action
      $auth_row,          # with these row values
      $self->key_cols(),  # identified by these key cols
      $change_dbh,        # on this dbh
   );
   return;
}

sub done_with_rows {
   my ( $self ) = @_;
   if ( $self->{state} == 1 ) {
      # The chunk of rows differed, now checksum the rows.
      $self->{state} = 2;
      PTDEBUG && _d('Setting state =', $self->{state});
   }
   else {
      # State might be 0 or 2.  If 0 then the chunk of rows was the same
      # and we move on to the next chunk.  If 2 then we just resolved any
      # row differences by calling not_in_left/right() so move on to the
      # next chunk.
      $self->{state} = 0;
      $self->{chunk_num}++;
      PTDEBUG && _d('Setting state =', $self->{state},
         'chunk_num =', $self->{chunk_num});
   }
   return;
}

sub done {
   my ( $self ) = @_;
   PTDEBUG && _d('Done with', $self->{chunk_num}, 'of',
      scalar(@{$self->{chunks}}), 'chunks');
   PTDEBUG && $self->{state} && _d('Chunk differs; must examine rows');
   return $self->{state} == 0
      && $self->{chunk_num} >= scalar(@{$self->{chunks}})
}

sub pending_changes {
   my ( $self ) = @_;
   if ( $self->{state} ) {
      PTDEBUG && _d('There are pending changes');
      # There are pending changes because in state 1 or 2 the chunk of rows
      # differs so there's at least 1 row that differs and needs to be changed.
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
      @cols = $self->{chunk_col};
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
# End TableSyncChunk package
# ###########################################################################
