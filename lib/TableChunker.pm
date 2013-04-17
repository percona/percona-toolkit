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
# TableChunker package
# ###########################################################################
{
# Package: TableChunker
# TableChunker helps determine how to "chunk" a table.  Chunk are
# pre-determined ranges of rows defined by boundary values (sometimes also
# called endpoints) on numeric or numeric-like columns, including date/time
# types.  Any numeric column type that MySQL can do positional comparisons
# (<, <=, >, >=) on works.  Chunking on character data is not supported yet
# (but see <issue 568 at http://code.google.com/p/maatkit/issues/detail?id=568>).
# 
# Usually chunks range over all rows in a table but sometimes they only
# range over a subset of rows if an optional where arg is passed to various
# subs.  In either case a chunk is like "`col` >= 5 AND `col` < 10".  If
# col is of type int and is unique, then that chunk ranges over up to 5 rows.
#
# Chunks are included in WHERE clauses by various tools to do work on discrete
# chunks of the table instead of trying to work on the entire table at once.
# Chunks do not overlap and their size is configurable via the chunk_size arg
# passed to several subs.  The chunk_size can be a number of rows or a size
# like 1M, in which case it's in estimated bytes of data.  Real chunk sizes
# are usually close to the requested chunk_size but unless the optional exact
# arg is assed the real chunk sizes are approximate.  Sometimes the
# distribution of values on the chunk colun can skew chunking.  If, for
# example, col has values 0, 100, 101, ... then the zero value skews chunking.
# The zero_chunk arg handles this.
package TableChunker;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use POSIX qw(floor ceil);
use List::Util qw(min max);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# Sub: new
#
# Parameters:
#   $class - TableChunker (automatic)
#   %args  - Arguments
#
# Required Arguments:
#   Quoter      - <Quoter> object
#   TableParser - <TableParser> object
sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(Quoter TableParser) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my %int_types  = map { $_ => 1 } qw(bigint date datetime int mediumint smallint time timestamp tinyint year);
   my %real_types = map { $_ => 1 } qw(decimal double float);

   my $self = {
      %args,
      int_types  => \%int_types,
      real_types => \%real_types,
      EPOCH      => '1970-01-01',
   };

   return bless $self, $class;
}

# Sub: find_chunk_columns
#   Find chunkable columns.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   table_struct - Hashref returned from <TableParser::parse()>
#
# Optional Arguments:
#   exact - bool: Try to support exact chunk sizes (may still chunk fuzzily)
#
# Returns:
#   Array: whether the table can be chunked exactly if requested (zero
#   otherwise), arrayref of columns that support chunking.  Example:
#   (start code)
#   1,
#   [
#     { column => 'id', index => 'PRIMARY' },
#     { column => 'i',  index => 'i_idx'   },
#   ]
#   (end code)
sub find_chunk_columns {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(tbl_struct) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $tbl_struct = $args{tbl_struct};

   # See if there's an index that will support chunking.
   my @possible_indexes;
   foreach my $index ( values %{ $tbl_struct->{keys} } ) {

      # Accept only BTREE indexes.
      next unless $index->{type} eq 'BTREE';

      # Reject indexes with prefixed columns.
      next if grep { defined } @{$index->{col_prefixes}};

      # If exact, accept only unique, single-column indexes.
      if ( $args{exact} ) {
         next unless $index->{is_unique} && @{$index->{cols}} == 1;
      }

      push @possible_indexes, $index;
   }
   PTDEBUG && _d('Possible chunk indexes in order:',
      join(', ', map { $_->{name} } @possible_indexes));

   # Build list of candidate chunk columns.   
   my $can_chunk_exact = 0;
   my @candidate_cols;
   foreach my $index ( @possible_indexes ) { 
      my $col = $index->{cols}->[0];

      # Accept only integer or real number type columns or character columns.
      my $col_type = $tbl_struct->{type_for}->{$col};
      next unless $self->{int_types}->{$col_type}
               || $self->{real_types}->{$col_type}
               || $col_type =~ m/char/;

      # Save the candidate column and its index.
      push @candidate_cols, { column => $col, index => $index->{name} };
   }

   $can_chunk_exact = 1 if $args{exact} && scalar @candidate_cols;

   if ( PTDEBUG ) {
      my $chunk_type = $args{exact} ? 'Exact' : 'Inexact';
      _d($chunk_type, 'chunkable:',
         join(', ', map { "$_->{column} on $_->{index}" } @candidate_cols));
   }

   # Order the candidates by their original column order.
   # Put the PK's first column first, if it's a candidate.
   my @result;
   PTDEBUG && _d('Ordering columns by order in tbl, PK first');
   if ( $tbl_struct->{keys}->{PRIMARY} ) {
      my $pk_first_col = $tbl_struct->{keys}->{PRIMARY}->{cols}->[0];
      @result          = grep { $_->{column} eq $pk_first_col } @candidate_cols;
      @candidate_cols  = grep { $_->{column} ne $pk_first_col } @candidate_cols;
   }
   my $i = 0;
   my %col_pos = map { $_ => $i++ } @{$tbl_struct->{cols}};
   push @result, sort { $col_pos{$a->{column}} <=> $col_pos{$b->{column}} }
                    @candidate_cols;

   if ( PTDEBUG ) {
      _d('Chunkable columns:',
         join(', ', map { "$_->{column} on $_->{index}" } @result));
      _d('Can chunk exactly:', $can_chunk_exact);
   }

   return ($can_chunk_exact, @result);
}

# Sub: calculate_chunks
#   Calculate chunks for the given range statistics.  Args min, max and
#   rows_in_range are returned from get_range_statistics() which is usually
#   called before this sub.  Min and max are expected to be valid values
#   (NULL is valid).
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dbh           - dbh
#   db            - database name
#   tbl           - table name
#   tbl_struct    - retval of <TableParser::parse()>
#   chunk_col     - column name to chunk on
#   min           - min col value, from <TableChunker::get_range_statistics()>
#   max           - max col value, from <TableChunker::get_range_statistics()>
#   rows_in_range - number of rows to chunk, from
#                   <TableChunker::get_range_statistics()>
#   chunk_size    - requested size of each chunk
#
# Optional Arguments:
#   exact       - Use exact chunk_size? Use approximates is not.
#   tries       - Fetch up to this many rows to find a non-zero value
#   chunk_range - Make chunk range open (default) or openclosed
#   where       - WHERE clause.
#
# Returns:
#   Array of WHERE predicates like "`col` >= '10' AND `col` < '20'",
#   one for each chunk.  All values are single-quoted due to <issue 1002 at
#   http://code.google.com/p/maatkit/issues/detail?id=1002>.  Example:
#   (start code)
#   `film_id` < '30',
#   `film_id` >= '30' AND `film_id` < '60',
#   `film_id` >= '60' AND `film_id` < '90',
#   `film_id` >= '90',
#   (end code)
sub calculate_chunks {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct chunk_col rows_in_range chunk_size);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   PTDEBUG && _d('Calculate chunks for',
      join(", ", map {"$_=".(defined $args{$_} ? $args{$_} : "undef")}
         qw(db tbl chunk_col min max rows_in_range chunk_size zero_chunk exact)
      ));

   if ( !$args{rows_in_range} ) {
      PTDEBUG && _d("Empty table");
      return '1=1';
   }

   # http://code.google.com/p/maatkit/issues/detail?id=1084
   if ( $args{rows_in_range} < $args{chunk_size} ) {
      PTDEBUG && _d("Chunk size larger than rows in range");
      return '1=1';
   }

   my $q          = $self->{Quoter};
   my $dbh        = $args{dbh};
   my $chunk_col  = $args{chunk_col};
   my $tbl_struct = $args{tbl_struct};
   my $col_type   = $tbl_struct->{type_for}->{$chunk_col};
   PTDEBUG && _d('chunk col type:', $col_type);

   # Get chunker info for the column type.  Numeric cols are chunked
   # differently than char cols.
   my %chunker;
   if ( $tbl_struct->{is_numeric}->{$chunk_col} || $col_type =~ /date|time/ ) {
      %chunker = $self->_chunk_numeric(%args);
   }
   elsif ( $col_type =~ m/char/ ) {
      %chunker = $self->_chunk_char(%args);
   }
   else {
      die "Cannot chunk $col_type columns";
   }
   PTDEBUG && _d("Chunker:", Dumper(\%chunker));
   my ($col, $start_point, $end_point, $interval, $range_func)
      = @chunker{qw(col start_point end_point interval range_func)};

   # Generate a list of chunk boundaries.  The first and last chunks are
   # inclusive, and will catch any rows before or after the end of the
   # supposed range.  So 1-100 divided into chunks of 30 should actually end
   # up with chunks like this:
   #           < 30
   # >= 30 AND < 60
   # >= 60 AND < 90
   # >= 90
   # If zero_chunk was specified and zero chunking was possible, the first
   # chunk will be = 0 to catch any zero or zero-equivalent (e.g. 00:00:00)
   # rows.
   my @chunks;
   if ( $start_point < $end_point ) {

      # The zero chunk, if there is one.  It doesn't have to be the first
      # chunk.  The 0 cannot be quoted because if d='0000-00-00' then
      # d=0 will work but d='0' will cause warning 1292: Incorrect date
      # value: '0' for column 'd'.  This might have to column-specific in
      # future when we chunk on more exotic column types.
      push @chunks, "$col = 0" if $chunker{have_zero_chunk};

      my ($beg, $end);
      my $iter = 0;
      for ( my $i = $start_point; $i < $end_point; $i += $interval ) {
         ($beg, $end) = $self->$range_func($dbh, $i, $interval, $end_point);

         # The first chunk.
         if ( $iter++ == 0 ) {
            push @chunks,
               ($chunker{have_zero_chunk} ? "$col > 0 AND " : "")
               ."$col < " . $q->quote_val($end);
         }
         else {
            # The normal case is a chunk in the middle of the range somewhere.
            push @chunks, "$col >= " . $q->quote_val($beg) . " AND $col < " . $q->quote_val($end);
         }
      }

      # Remove the last chunk and replace it with one that matches everything
      # from the beginning of the last chunk to infinity, or to the max col
      # value if chunk_range is openclosed.  If the chunk column is nullable,
      # do NULL separately.
      my $chunk_range = lc($args{chunk_range} || 'open');
      my $nullable    = $args{tbl_struct}->{is_nullable}->{$args{chunk_col}};
      pop @chunks;
      if ( @chunks ) {
         push @chunks, "$col >= " . $q->quote_val($beg)
            . ($chunk_range eq 'openclosed'
               ? " AND $col <= " . $q->quote_val($args{max}) : "");
      }
      else {
         push @chunks, $nullable ? "$col IS NOT NULL" : '1=1';
      }
      if ( $nullable ) {
         push @chunks, "$col IS NULL";
      }
   }
   else {
      # There are no chunks; just do the whole table in one chunk.
      PTDEBUG && _d('No chunks; using single chunk 1=1');
      push @chunks, '1=1';
   }

   return @chunks;
}

# Sub: _chunk_numeric
#   Determine how to chunk a numeric column.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dbh           - dbh
#   db            - database name
#   tbl           - table name
#   tbl_struct    - retval of <TableParser::parse()>
#   chunk_col     - column name to chunk on
#   min           - min col value, from <TableChunker::get_range_statistics()>
#   max           - max col value, from <TableChunker::get_range_statistics()>
#   rows_in_range - number of rows to chunk, from
#                   <TableChunker::get_range_statistics()>
#   chunk_size    - requested size of each chunk
#
# Optional Arguments:
#   exact      - Use exact chunk_size? Use approximates is not.
#   tries      - Fetch up to this many rows to find a non-zero value
#   zero_chunk - Add an extra chunk for zero values? (0, 00:00, etc.)
#
# Returns:
#   Array of chunker info that <calculate_chunks()> uses to create
#   chunks, like:
#   (start code)
#   col             => quoted chunk column name
#   start_point     => start value (a Perl number)
#   end_point       => end value (a Perl number)
#   interval        => interval to walk from start_ to end_point (a Perl number)
#   range_func      => coderef to return a value while walking that ^ range
#   have_zero_chunk => whether to include a zero chunk (col=0)
#   (end code)
sub _chunk_numeric {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct chunk_col rows_in_range chunk_size);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $q        = $self->{Quoter};
   my $db_tbl   = $q->quote($args{db}, $args{tbl});
   my $col_type = $args{tbl_struct}->{type_for}->{$args{chunk_col}};

   # Convert the given MySQL values to (Perl) numbers using some MySQL function.
   # E.g.: SELECT TIME_TO_SEC('12:34') == 45240.  
   my $range_func;
   if ( $col_type =~ m/(?:int|year|float|double|decimal)$/ ) {
      $range_func  = 'range_num';
   }
   elsif ( $col_type =~ m/^(?:timestamp|date|time)$/ ) {
      $range_func  = "range_$col_type";
   }
   elsif ( $col_type eq 'datetime' ) {
      $range_func  = 'range_datetime';
   }

   my ($start_point, $end_point);
   eval {
      $start_point = $self->value_to_number(
         value       => $args{min},
         column_type => $col_type,
         dbh         => $args{dbh},
      );
      $end_point  = $self->value_to_number(
         value       => $args{max},
         column_type => $col_type,
         dbh         => $args{dbh},
      );
   };
   if ( $EVAL_ERROR ) {
      if ( $EVAL_ERROR =~ m/don't know how to chunk/ ) {
         # Special kind of error doesn't make sense with the more verbose
         # description below.
         die $EVAL_ERROR;
      }
      else {
         die "Error calculating chunk start and end points for table "
            . "`$args{tbl_struct}->{name}` on column `$args{chunk_col}` "
            . "with min/max values "
            . join('/',
                  map { defined $args{$_} ? $args{$_} : 'undef' } qw(min max))
            . ":\n\n"
            . $EVAL_ERROR
            . "\nVerify that the min and max values are valid for the column.  "
            . "If they are valid, this error could be caused by a bug in the "
            . "tool.";
      }
   }

   # The end points might be NULL in the pathological case that the table
   # has nothing but NULL values.  If there's at least one non-NULL value
   # then MIN() and MAX() will return it.  Otherwise, the only thing to do
   # is make NULL end points zero to make the code below work and any NULL
   # values will be handled by the special "IS NULL" chunk.
   if ( !defined $start_point ) {
      PTDEBUG && _d('Start point is undefined');
      $start_point = 0;
   }
   if ( !defined $end_point || $end_point < $start_point ) {
      PTDEBUG && _d('End point is undefined or before start point');
      $end_point = 0;
   }
   PTDEBUG && _d("Actual chunk range:", $start_point, "to", $end_point);

   # Determine if we can include a zero chunk (col = 0).  If yes, then
   # make sure the start point is non-zero.  $start_point and $end_point
   # should be numbers (converted from MySQL values earlier).  The purpose
   # of the zero chunk is to capture a potentially large number of zero
   # values that might imbalance the size of the first chunk.  E.g. if a
   # lot of invalid times were inserted and stored as 00:00:00, these
   # zero (equivalent) values are captured by the zero chunk instead of
   # the first chunk + all the non-zero values in the first chunk.
   my $have_zero_chunk = 0;
   if ( $args{zero_chunk} ) {
      if ( $start_point != $end_point && $start_point >= 0 ) {
         PTDEBUG && _d('Zero chunking');
         my $nonzero_val = $self->get_nonzero_value(
            %args,
            db_tbl   => $db_tbl,
            col      => $args{chunk_col},
            col_type => $col_type,
            val      => $args{min}
         );
         # Since we called value_to_number() before with this column type
         # we shouldn't have to worry about it dying here--it would have
         # died earlier if we can't chunk the column type.
         $start_point = $self->value_to_number(
            value       => $nonzero_val,
            column_type => $col_type,
            dbh         => $args{dbh},
         );
         $have_zero_chunk = 1;
      }
      else {
         PTDEBUG && _d("Cannot zero chunk");
      }
   }
   PTDEBUG && _d("Using chunk range:", $start_point, "to", $end_point);

   # Calculate the chunk size in terms of "distance between endpoints"
   # that will give approximately the right number of rows between the
   # endpoints.  If possible and requested, forbid chunks from being any
   # bigger than specified.
   my $interval = $args{chunk_size}
                * ($end_point - $start_point)
                / $args{rows_in_range};
   if ( $self->{int_types}->{$col_type} ) {
      $interval = ceil($interval);
   }
   $interval ||= $args{chunk_size};
   if ( $args{exact} ) {
      $interval = $args{chunk_size};
   }
   PTDEBUG && _d('Chunk interval:', $interval, 'units');

   return (
      col             => $q->quote($args{chunk_col}),
      start_point     => $start_point,
      end_point       => $end_point,
      interval        => $interval,
      range_func      => $range_func,
      have_zero_chunk => $have_zero_chunk,
   );
}

# Sub: _chunk_numeric
#   Determine how to chunk a character column.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dbh           - dbh
#   db            - database name
#   tbl           - table name
#   tbl_struct    - retval of <TableParser::parse()>
#   chunk_col     - column name to chunk on
#   min           - min col value, from <TableChunker::get_range_statistics()>
#   max           - max col value, from <TableChunker::get_range_statistics()>
#   rows_in_range - number of rows to chunk, from
#                   <TableChunker::get_range_statistics()>
#   chunk_size    - requested size of each chunk
#
# Optional Arguments:
#   where - WHERE clause.
#
# Returns:
#   Array of chunker info that <calculate_chunks()> uses to create
#   chunks, like:
#   (start code)
#   col             => quoted chunk column name
#   start_point     => start value (a Perl number)
#   end_point       => end value (a Perl number)
#   interval        => interval to walk from start_ to end_point (a Perl number)
#   range_func      => coderef to return a value while walking that ^ range
#   (end code)
sub _chunk_char {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct chunk_col min max rows_in_range chunk_size);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $q          = $self->{Quoter};
   my $db_tbl     = $q->quote($args{db}, $args{tbl});
   my $dbh        = $args{dbh};
   my $chunk_col  = $args{chunk_col};
   my $qchunk_col = $q->quote($args{chunk_col});
   my $row;
   my $sql;

   # Get the character codes between the min and max column values.
   my ($min_col, $max_col) = @{args}{qw(min max)};
   $sql = "SELECT ORD(?) AS min_col_ord, ORD(?) AS max_col_ord";
   PTDEBUG && _d($dbh, $sql);
   my $ord_sth = $dbh->prepare($sql);  # avoid quoting issues
   $ord_sth->execute($min_col, $max_col);
   $row = $ord_sth->fetchrow_arrayref();
   my ($min_col_ord, $max_col_ord) = ($row->[0], $row->[1]);
   PTDEBUG && _d("Min/max col char code:", $min_col_ord, $max_col_ord);

   # Create a sorted chacater-to-number map of the unique characters in
   # the column ranging from the min character code to the max.
   my $base;
   my @chars;
   PTDEBUG && _d("Table charset:", $args{tbl_struct}->{charset});
   if ( ($args{tbl_struct}->{charset} || "") eq "latin1" ) {
      # These are the unique, sorted latin1 character codes according to
      # MySQL.  You'll notice that many are missing.  That's because MySQL
      # treats many characters as the same, for example "e" and "é".
      my @sorted_latin1_chars = (
          32,  33,  34,  35,  36,  37,  38,  39,  40,  41,  42,  43,  44,  45,
          46,  47,  48,  49,  50,  51,  52,  53,  54,  55,  56,  57,  58,  59,
          60,  61,  62,  63,  64,  65,  66,  67,  68,  69,  70,  71,  72,  73,
          74,  75,  76,  77,  78,  79,  80,  81,  82,  83,  84,  85,  86,  87,
          88,  89,  90,  91,  92,  93,  94,  95,  96, 123, 124, 125, 126, 161,
         162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175,
         176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189,
         190, 191, 215, 216, 222, 223, 247, 255);

      my ($first_char, $last_char);
      for my $i ( 0..$#sorted_latin1_chars ) {
         $first_char = $i and last if $sorted_latin1_chars[$i] >= $min_col_ord;
      }
      for my $i ( $first_char..$#sorted_latin1_chars ) {
         $last_char = $i and last if $sorted_latin1_chars[$i] >= $max_col_ord;
      };

      @chars = map { chr $_; } @sorted_latin1_chars[$first_char..$last_char];
      $base  = scalar @chars;
   }
   else {
      # If the table's charset isn't latin1, who knows what charset is being
      # used, what characters it contains, and how those characters are sorted.
      # So we create a character map and let MySQL tell us these things.

      # Create a temp table with the same char col def as the original table.
      my $tmp_tbl    = '__maatkit_char_chunking_map';
      my $tmp_db_tbl = $q->quote($args{db}, $tmp_tbl);
      $sql = "DROP TABLE IF EXISTS $tmp_db_tbl";
      PTDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
      my $col_def = $args{tbl_struct}->{defs}->{$chunk_col};
      $sql        = "CREATE TEMPORARY TABLE $tmp_db_tbl ($col_def) "
                  . "ENGINE=MEMORY";
      PTDEBUG && _d($dbh, $sql);
      $dbh->do($sql);

      # Populate the temp table with all the characters between the min and max
      # max character codes.  This is our character-to-number map.
      $sql = "INSERT INTO $tmp_db_tbl VALUES (CHAR(?))";
      PTDEBUG && _d($dbh, $sql);
      my $ins_char_sth = $dbh->prepare($sql);  # avoid quoting issues
      for my $char_code ( $min_col_ord..$max_col_ord ) {
         $ins_char_sth->execute($char_code);
      }

      # Select from the char-to-number map all characters between the
      # min and max col values, letting MySQL order them.  The first
      # character returned becomes "zero" in a new base system of counting,
      # the second character becomes "one", etc.  So if 42 chars are
      # returned like [a, B, c, d, é, ..., ü] then we have a base 42
      # system where 0=a, 1=B, 2=c, 3=d, 4=é, ... 41=ü.  count_base()
      # helps us count in arbitrary systems.
      $sql = "SELECT $qchunk_col FROM $tmp_db_tbl "
           . "WHERE $qchunk_col BETWEEN ? AND ? "
           . "ORDER BY $qchunk_col";
      PTDEBUG && _d($dbh, $sql);
      my $sel_char_sth = $dbh->prepare($sql);
      $sel_char_sth->execute($min_col, $max_col);

      @chars = map { $_->[0] } @{ $sel_char_sth->fetchall_arrayref() };
      $base  = scalar @chars;

      $sql = "DROP TABLE $tmp_db_tbl";
      PTDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }
   PTDEBUG && _d("Base", $base, "chars:", @chars);

   # See https://bugs.launchpad.net/percona-toolkit/+bug/1034717
   die "Cannot chunk table $db_tbl using the character column "
     . "$chunk_col, most likely because all values start with the "
     . "same character.  This table must be synced separately by "
     . "specifying a list of --algorithms without the Chunk algorithm"
      if $base == 1;

   # Now we begin calculating how to chunk the char column.  This is
   # completely different from _chunk_numeric because we're not dealing
   # with the values to chunk directly (the characters) but rather a map.

   # In our base system, how many values can 1, 2, etc. characters express?
   # E.g. in a base 26 system (a-z), 1 char expresses 26^1=26 chars (a-z),
   # 2 chars expresses 26^2=676 chars.  If the requested chunk size is 100,
   # then 1 char might not express enough values, but 2 surely can.  This
   # is imperefect because we don't know if we have data like: [apple, boy,
   # car] (i.e. values evenly distributed across the range of chars), or
   # [ant, apple, azur, boy].  We assume data is more evenly distributed
   # than not so we use the minimum number of characters to express a chunk
   # size.
   $sql = "SELECT MAX(LENGTH($qchunk_col)) FROM $db_tbl "
        . ($args{where} ? "WHERE $args{where} " : "") 
        . "ORDER BY $qchunk_col";
   PTDEBUG && _d($dbh, $sql);
   $row = $dbh->selectrow_arrayref($sql);
   my $max_col_len = $row->[0];
   PTDEBUG && _d("Max column value:", $max_col, $max_col_len);
   my $n_values;
   for my $n_chars ( 1..$max_col_len ) {
      $n_values = $base**$n_chars;
      if ( $n_values >= $args{chunk_size} ) {
         PTDEBUG && _d($n_chars, "chars in base", $base, "expresses",
            $n_values, "values");
         last;
      }
   }

   # Our interval is not like a _chunk_numeric() interval, either, because
   # we don't increment in the actual values (i.e. the characters) but rather
   # in the char-to-number map.  If the above calculation found that 1 char
   # expressed enough values for 1 chunk, then each char in the map will
   # yield roughly one chunk of values, so the interval is 1.  Or, if we need
   # 2 chars to express enough vals for 1 chunk, then we'll increment through
   # the map 2 chars at a time, like [a, b], [c, d], etc.
   my $n_chunks = $args{rows_in_range} / $args{chunk_size};
   my $interval = floor(($n_values+0.00001) / $n_chunks) || 1;

   my $range_func = sub {
      my ( $self, $dbh, $start, $interval, $max ) = @_;
      my $start_char = $self->base_count(
         count_to => $start,
         base     => $base,
         symbols  => \@chars,
      );
      my $end_char = $self->base_count(
         count_to => min($max, $start + $interval),
         base     => $base,
         symbols  => \@chars,
      );
      return $start_char, $end_char;
   };

   return (
      col         => $qchunk_col,
      start_point => 0,
      end_point   => $n_values,
      interval    => $interval,
      range_func  => $range_func,
   );
}

# Sub: get_first_chunkable_column
#   Get the first chunkable column in a table.
#   Only a "sane" column/index is returned.  That means that
#   the first auto-detected chunk col/index are used if any combination of
#   preferred chunk col or index would be really bad, like chunk col=x
#   and chunk index=some index over (y, z).  That's bad because the index
#   doesn't include the column; it would also be bad if the column wasn't
#   a left-most prefix of the index.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   tbl_struct - Hashref returned by <TableParser::parse()>
#
# Optional arguments:
#   chunk_column - Preferred chunkable column name
#   chunk_index  - Preferred chunkable column index name
#   exact        - bool: passed to <find_chunk_columns()>
#
# Returns:
#   List: chunkable column name, chunkable colum index
sub get_first_chunkable_column {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(tbl_struct) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   # First auto-detected chunk col/index.  If any combination of preferred 
   # chunk col or index are specified and are sane, they will overwrite
   # these defaults.  Else, these defaults will be returned.
   my ($exact, @cols) = $self->find_chunk_columns(%args);
   my $col = $cols[0]->{column};
   my $idx = $cols[0]->{index};

   # Wanted/preferred chunk column and index.  Caller only gets what
   # they want, though, if it results in a sane col/index pair.
   my $wanted_col = $args{chunk_column};
   my $wanted_idx = $args{chunk_index};
   PTDEBUG && _d("Preferred chunk col/idx:", $wanted_col, $wanted_idx);

   if ( $wanted_col && $wanted_idx ) {
      # Preferred column and index: check that the pair is sane.
      foreach my $chunkable_col ( @cols ) {
         if (    $wanted_col eq $chunkable_col->{column}
              && $wanted_idx eq $chunkable_col->{index} ) {
            # The wanted column is chunkable with the wanted index.
            $col = $wanted_col;
            $idx = $wanted_idx;
            last;
         }
      }
   }
   elsif ( $wanted_col ) {
      # Preferred column, no index: check if column is chunkable, if yes
      # then use its index, else fall back to default col/index.
      foreach my $chunkable_col ( @cols ) {
         if ( $wanted_col eq $chunkable_col->{column} ) {
            # The wanted column is chunkable, so use its index and overwrite
            # the defaults.
            $col = $wanted_col;
            $idx = $chunkable_col->{index};
            last;
         }
      }
   }
   elsif ( $wanted_idx ) {
      # Preferred index, no column: check if index's left-most column is
      # chunkable, if yes then use its column, else fall back to auto-detected
      # col/index.
      foreach my $chunkable_col ( @cols ) {
         if ( $wanted_idx eq $chunkable_col->{index} ) {
            # The wanted index has a chunkable column, so use it and overwrite
            # the defaults.
            $col = $chunkable_col->{column};
            $idx = $wanted_idx;
            last;
         }
      }
   }

   PTDEBUG && _d('First chunkable col/index:', $col, $idx);
   return $col, $idx;
}

# Sub: size_to_rows
#   Convert a size in rows or bytes to a number of rows in the table,
#   using SHOW TABLE STATUS.  If the size is a string with a suffix of M/G/k,
#   interpret it as mebibytes, gibibytes, or kibibytes respectively.
#   If it's just a number, treat it as a number of rows and return right away.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dbh        - dbh
#   db         - Database name
#   tbl        - Table name
#   chunk_size - Chunk size string like "1000" or "50M"
#
# Returns:
#   Array: number of rows, average row size
sub size_to_rows {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl chunk_size);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $tbl, $chunk_size) = @args{@required_args};
   my $q  = $self->{Quoter};
   my $tp = $self->{TableParser};

   my ($n_rows, $avg_row_length);

   my ( $num, $suffix ) = $chunk_size =~ m/^(\d+)([MGk])?$/;
   if ( $suffix ) { # Convert to bytes.
      $chunk_size = $suffix eq 'k' ? $num * 1_024
                  : $suffix eq 'M' ? $num * 1_024 * 1_024
                  :                  $num * 1_024 * 1_024 * 1_024;
   }
   elsif ( $num ) {
      $n_rows = $num;
   }
   else {
      die "Invalid chunk size $chunk_size; must be an integer "
         . "with optional suffix kMG";
   }

   if ( $suffix || $args{avg_row_length} ) {
      my ($status) = $tp->get_table_status($dbh, $db, $tbl);
      $avg_row_length = $status->{avg_row_length};
      if ( !defined $n_rows ) {
         $n_rows = $avg_row_length ? ceil($chunk_size / $avg_row_length) : undef;
      }
   }

   return $n_rows, $avg_row_length;
}

# Sub: get_range_statistics
#   Determine the range of values for the chunk_col column on this table.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dbh        - dbh
#   db         - Database name
#   tbl        - Table name
#   chunk_col  - Chunk column name
#   tbl_struct - Hashref returned by <TableParser::parse()>
#
# Optional arguments:
#   where      - WHERE clause without "WHERE" to restrict range
#   index_hint - "FORCE INDEX (...)" clause
#   tries      - Fetch up to this many rows to find a valid value
#
# Returns:
#   Array: min row value, max row value, rows in range 
sub get_range_statistics {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl chunk_col tbl_struct);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $tbl, $col) = @args{@required_args};
   my $where = $args{where};
   my $q     = $self->{Quoter};

   my $col_type       = $args{tbl_struct}->{type_for}->{$col};
   my $col_is_numeric = $args{tbl_struct}->{is_numeric}->{$col};

   # Quote these once so we don't have to do it again. 
   my $db_tbl = $q->quote($db, $tbl);
   $col       = $q->quote($col);

   my ($min, $max);
   eval {
      # First get the actual end points, whatever MySQL considers the
      # min and max values to be for this column.
      my $sql = "SELECT MIN($col), MAX($col) FROM $db_tbl"
              . ($args{index_hint} ? " $args{index_hint}" : "")
              . ($where ? " WHERE ($where)" : '');
      PTDEBUG && _d($dbh, $sql);
      ($min, $max) = $dbh->selectrow_array($sql);
      PTDEBUG && _d("Actual end points:", $min, $max);

      # Now, for two reasons, get the valid end points.  For one, an
      # end point may be 0 or some zero-equivalent and the user doesn't
      # want that because it skews the range.  Or two, an end point may
      # be an invalid value like date 2010-00-00 and we can't use that.
      ($min, $max) = $self->get_valid_end_points(
         %args,
         dbh      => $dbh,
         db_tbl   => $db_tbl,
         col      => $col,
         col_type => $col_type,
         min      => $min,
         max      => $max,
      );
      PTDEBUG && _d("Valid end points:", $min, $max);
   };
   if ( $EVAL_ERROR ) {
      die "Error getting min and max values for table $db_tbl "
         . "on column $col: $EVAL_ERROR";
   }

   # Finally get the total number of rows in range, usually the whole
   # table unless there's a where arg restricting the range.
   my $sql = "EXPLAIN SELECT * FROM $db_tbl"
           . ($args{index_hint} ? " $args{index_hint}" : "")
           . ($where ? " WHERE $where" : '');
   PTDEBUG && _d($sql);
   my $expl = $dbh->selectrow_hashref($sql);

   return (
      min           => $min,
      max           => $max,
      rows_in_range => $expl->{rows},
   );
}

# Sub: inject_chunks
#   Create a SQL statement from a query prototype by filling in placeholders.
# 
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   database  - Database name
#   table     - Table name
#   chunks    - Arrayref of chunks from <calculate_chunks()>
#   chunk_num - Index into chunks to use
#   query     - Query prototype returned by
#               <TableChecksum::make_checksum_query()>
#
# Optional Arguments:
#   index_hint - "FORCE INDEX (...)" clause
#   where      - Arrayref of WHERE clauses joined with AND
#
# Returns:
#   A SQL statement
sub inject_chunks {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(database table chunks chunk_num query) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   PTDEBUG && _d('Injecting chunk', $args{chunk_num});
   my $query   = $args{query};
   my $comment = sprintf("/*%s.%s:%d/%d*/",
      $args{database}, $args{table},
      $args{chunk_num} + 1, scalar @{$args{chunks}});
   $query =~ s!/\*PROGRESS_COMMENT\*/!$comment!;
   my $where = "WHERE (" . $args{chunks}->[$args{chunk_num}] . ')';
   if ( $args{where} && grep { $_ } @{$args{where}} ) {
      $where .= " AND ("
         . join(" AND ", map { "($_)" } grep { $_ } @{$args{where}} )
         . ")";
   }
   my $db_tbl     = $self->{Quoter}->quote(@args{qw(database table)});
   my $index_hint = $args{index_hint} || '';

   PTDEBUG && _d('Parameters:',
      Dumper({WHERE => $where, DB_TBL => $db_tbl, INDEX_HINT => $index_hint}));
   $query =~ s!/\*WHERE\*/! $where!;
   $query =~ s!/\*DB_TBL\*/!$db_tbl!;
   $query =~ s!/\*INDEX_HINT\*/! $index_hint!;
   $query =~ s!/\*CHUNK_NUM\*/! $args{chunk_num} AS chunk_num,!;

   return $query;
}

# #############################################################################
# MySQL value to Perl number conversion.
# #############################################################################

# Convert a MySQL column value to a Perl integer.
# Arguments:
#   * value       scalar: MySQL value to convert
#   * column_type scalar: MySQL column type of the value
#   * dbh         dbh
# Returns an integer or undef if the value isn't convertible
# (e.g. date 0000-00-00 is not convertible).
sub value_to_number {
   my ( $self, %args ) = @_;
   my @required_args = qw(column_type dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $val = $args{value};
   my ($col_type, $dbh) = @args{@required_args};
   PTDEBUG && _d('Converting MySQL', $col_type, $val);

   return unless defined $val;  # value is NULL

   # MySQL functions to convert a non-numeric value to a number
   # so we can do basic math on it in Perl.  Right now we just
   # convert temporal values but later we'll need to convert char
   # and hex values.
   my %mysql_conv_func_for = (
      timestamp => 'UNIX_TIMESTAMP',
      date      => 'TO_DAYS',
      time      => 'TIME_TO_SEC',
      datetime  => 'TO_DAYS',
   );

   # Convert the value to a number that Perl can do arithmetic with.
   my $num;
   if ( $col_type =~ m/(?:int|year|float|double|decimal)$/ ) {
      # These types are already numbers.
      $num = $val;
   }
   elsif ( $col_type =~ m/^(?:timestamp|date|time)$/ ) {
      # These are temporal values.  Convert them using a MySQL func.
      my $func = $mysql_conv_func_for{$col_type};
      my $sql = "SELECT $func(?)";
      PTDEBUG && _d($dbh, $sql, $val);
      my $sth = $dbh->prepare($sql);
      $sth->execute($val);
      ($num) = $sth->fetchrow_array();
   }
   elsif ( $col_type eq 'datetime' ) {
      # This type is temporal, too, but needs special handling.
      # Newer versions of MySQL could use TIMESTAMPDIFF, but it's easier
      # to maintain just one kind of code, so I do it all with DATE_ADD().
      $num = $self->timestampdiff($dbh, $val);
   }
   else {
      die "I don't know how to chunk $col_type\n";
   }
   PTDEBUG && _d('Converts to', $num);
   return $num;
}

# ###########################################################################
# Range functions.
# ###########################################################################
sub range_num {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $end = min($max, $start + $interval);


   # "Remove" scientific notation so the regex below does not make
   # 6.123456e+18 into 6.12345.
   $start = sprintf('%.17f', $start) if $start =~ /e/;
   $end   = sprintf('%.17f', $end)   if $end   =~ /e/;

   # Trim decimal places, if needed.  This helps avoid issues with float
   # precision differing on different platforms.
   $start =~ s/\.(\d{5}).*$/.$1/;
   $end   =~ s/\.(\d{5}).*$/.$1/;

   if ( $end > $start ) {
      return ( $start, $end );
   }
   else {
      die "Chunk size is too small: $end !> $start\n";
   }
}

sub range_time {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $sql = "SELECT SEC_TO_TIME($start), SEC_TO_TIME(LEAST($max, $start + $interval))";
   PTDEBUG && _d($sql);
   return $dbh->selectrow_array($sql);
}

sub range_date {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $sql = "SELECT FROM_DAYS($start), FROM_DAYS(LEAST($max, $start + $interval))";
   PTDEBUG && _d($sql);
   return $dbh->selectrow_array($sql);
}

sub range_datetime {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $sql = "SELECT DATE_ADD('$self->{EPOCH}', INTERVAL $start SECOND), "
       . "DATE_ADD('$self->{EPOCH}', INTERVAL LEAST($max, $start + $interval) SECOND)";
   PTDEBUG && _d($sql);
   return $dbh->selectrow_array($sql);
}

sub range_timestamp {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $sql = "SELECT FROM_UNIXTIME($start), FROM_UNIXTIME(LEAST($max, $start + $interval))";
   PTDEBUG && _d($sql);
   return $dbh->selectrow_array($sql);
}

# Returns the number of seconds between EPOCH and the value, according to
# the MySQL server.  (The server can do no wrong).  I believe this code is right
# after looking at the source of sql/time.cc but I am paranoid and add in an
# extra check just to make sure.  Earlier versions overflow on large interval
# values, such as on 3.23.58, '1970-01-01' - interval 58000000000 second is
# 2037-06-25 11:29:04.  I know of no workaround.  TO_DAYS('0000-....') is NULL,
# so we treat it as 0.
sub timestampdiff {
   my ( $self, $dbh, $time ) = @_;
   my $sql = "SELECT (COALESCE(TO_DAYS('$time'), 0) * 86400 + TIME_TO_SEC('$time')) "
      . "- TO_DAYS('$self->{EPOCH} 00:00:00') * 86400";
   PTDEBUG && _d($sql);
   my ( $diff ) = $dbh->selectrow_array($sql);
   $sql = "SELECT DATE_ADD('$self->{EPOCH}', INTERVAL $diff SECOND)";
   PTDEBUG && _d($sql);
   my ( $check ) = $dbh->selectrow_array($sql);
   die <<"   EOF"
   Incorrect datetime math: given $time, calculated $diff but checked to $check.
   This could be due to a version of MySQL that overflows on large interval
   values to DATE_ADD(), or the given datetime is not a valid date.  If not,
   please report this as a bug.
   EOF
      unless $check eq $time;
   return $diff;
}


# #############################################################################
# End point validation.
# #############################################################################

# These sub require val (or min and max) args which usually aren't NULL
# but could be zero so the usual "die ... unless $args{$arg}" check does
# not work.

# Returns valid min and max values.  A valid val evaluates to a non-NULL value.
# Arguments:
#   * dbh       dbh
#   * db_tbl    scalar: quoted `db`.`tbl`
#   * col       scalar: quoted `column`
#   * col_type  scalar: column type of the value
#   * min       scalar: any scalar value
#   * max       scalar: any scalar value
# Optional arguments:
#   * index_hint scalar: "FORCE INDEX (...)" hint
#   * where      scalar: WHERE clause without "WHERE"
#   * tries      scalar: fetch up to this many rows to find a valid value
#   * zero_chunk bool: do a separate chunk for zero values
# Some column types can store invalid values, like most of the temporal
# types.  When evaluated, invalid values return NULL.  If the value is
# NULL to begin with, then it is not invalid because NULL is valid.
# For example, TO_DAYS('2009-00-00') evalues to NULL because that date
# is invalid, even though it's storable.
sub get_valid_end_points {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db_tbl col col_type);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db_tbl, $col, $col_type) = @args{@required_args};
   my ($real_min, $real_max)           = @args{qw(min max)};

   # Common error message format in case there's a problem with
   # finding a valid min or max value.
   my $err_fmt = "Error finding a valid %s value for table $db_tbl on "
               . "column $col. The real %s value %s is invalid and "
               . "no other valid values were found.  Verify that the table "
               . "has at least one valid value for this column"
               . ($args{where} ? " where $args{where}." : ".");

   # Validate min value if it's not NULL.  NULL is valid.
   my $valid_min = $real_min;
   if ( defined $valid_min ) {
      # Get a valid min end point.
      PTDEBUG && _d("Validating min end point:", $real_min);
      $valid_min = $self->_get_valid_end_point(
         %args,
         val      => $real_min,
         endpoint => 'min',
      );
      die sprintf($err_fmt, 'minimum', 'minimum',
         (defined $real_min ? $real_min : "NULL"))
         unless defined $valid_min;
   }

   # Validate max value if it's not NULL.  NULL is valid.
   my $valid_max = $real_max;
   if ( defined $valid_max ) {
      # Get a valid max end point.  So far I've not found a case where
      # the actual max val is invalid, but check anyway just in case.
      PTDEBUG && _d("Validating max end point:", $real_min);
      $valid_max = $self->_get_valid_end_point(
         %args,
         val      => $real_max,
         endpoint => 'max',
      );
      die sprintf($err_fmt, 'maximum', 'maximum',
         (defined $real_max ? $real_max : "NULL"))
         unless defined $valid_max;
   }

   return $valid_min, $valid_max;
}

# Does the actual work for get_valid_end_points() for each end point.
sub _get_valid_end_point {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db_tbl col col_type);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db_tbl, $col, $col_type) = @args{@required_args};
   my $val = $args{val};

   # NULL is valid.
   return $val unless defined $val;

   # Right now we only validate temporal types, but when we begin
   # chunking char and hex columns we'll need to validate those.
   # E.g. HEX('abcdefg') is invalid and we'll probably find some
   # combination of char val + charset/collation that's invalid.
   my $validate = $col_type =~ m/time|date/ ? \&_validate_temporal_value
                :                             undef;

   # If we cannot validate the value, assume it's valid.
   if ( !$validate ) {
      PTDEBUG && _d("No validator for", $col_type, "values");
      return $val;
   }

   # Return the value if it's already valid.
   return $val if defined $validate->($dbh, $val);

   # The value is not valid so find the first one in the table that is.
   PTDEBUG && _d("Value is invalid, getting first valid value");
   $val = $self->get_first_valid_value(
      %args,
      val      => $val,
      validate => $validate,
   );

   return $val;
}

# Arguments:
#   * dbh       dbh
#   * db_tbl    scalar: quoted `db`.`tbl`
#   * col       scalar: quoted `column` name
#   * val       scalar: the current value, may be real, maybe not
#   * validate  coderef: returns a defined value if the given value is valid
#   * endpoint  scalar: "min" or "max", i.e. find first endpoint() real val
# Optional arguments:
#   * tries      scalar: fetch up to this many rows to find a valid value
#   * index_hint scalar: "FORCE INDEX (...)" hint
#   * where      scalar: WHERE clause without "WHERE"
# Returns the first column value from the given db_tbl that does *not*
# evaluate to NULL.  This is used mostly to eliminate unreal temporal
# values which MySQL allows to be stored, like "2010-00-00".  Returns
# undef if no real value is found.
sub get_first_valid_value {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db_tbl col validate endpoint);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db_tbl, $col, $validate, $endpoint) = @args{@required_args};
   my $tries = defined $args{tries} ? $args{tries} : 5;
   my $val   = $args{val};

   # NULL values are valid and shouldn't be passed to us.
   return unless defined $val;

   # Prep a sth for fetching the next col val.
   my $cmp = $endpoint =~ m/min/i ? '>'
           : $endpoint =~ m/max/i ? '<'
           :                        die "Invalid endpoint arg: $endpoint";
   my $sql = "SELECT $col FROM $db_tbl "
           . ($args{index_hint} ? "$args{index_hint} " : "")
           . "WHERE $col $cmp ? AND $col IS NOT NULL "
           . ($args{where} ? "AND ($args{where}) " : "")
           . "ORDER BY $col LIMIT 1";
   PTDEBUG && _d($dbh, $sql);
   my $sth = $dbh->prepare($sql);

   # Fetch the next col val from the db.tbl until we find a valid one
   # or run out of rows.  Only try a limited number of next rows.
   my $last_val = $val;
   while ( $tries-- ) {
      $sth->execute($last_val);
      my ($next_val) = $sth->fetchrow_array();
      PTDEBUG && _d('Next value:', $next_val, '; tries left:', $tries);
      if ( !defined $next_val ) {
         PTDEBUG && _d('No more rows in table');
         last;
      }
      if ( defined $validate->($dbh, $next_val) ) {
         PTDEBUG && _d('First valid value:', $next_val);
         $sth->finish();
         return $next_val;
      }
      $last_val = $next_val;
   }
   $sth->finish();
   $val = undef;  # no valid value found

   return $val;
}

# Evalutes any temporal value, returns NULL if it's invalid, else returns
# a value (possibly zero). It's magical but tested.  See also,
# http://hackmysql.com/blog/2010/05/26/detecting-invalid-and-zero-temporal-values/
sub _validate_temporal_value {
   my ( $dbh, $val ) = @_;
   my $sql = "SELECT IF(TIME_FORMAT(?,'%H:%i:%s')=?, TIME_TO_SEC(?), TO_DAYS(?))";
   my $res;
   eval {
      PTDEBUG && _d($dbh, $sql, $val);
      my $sth = $dbh->prepare($sql);
      $sth->execute($val, $val, $val, $val);
      ($res) = $sth->fetchrow_array();
      $sth->finish();
   };
   if ( $EVAL_ERROR ) {
      PTDEBUG && _d($EVAL_ERROR);
   }
   return $res;
}

sub get_nonzero_value {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db_tbl col col_type);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db_tbl, $col, $col_type) = @args{@required_args};
   my $tries = defined $args{tries} ? $args{tries} : 5;
   my $val   = $args{val};

   # Right now we only need a special check for temporal values.
   # _validate_temporal_value() does double-duty for this.  The
   # default anonymous sub handles ints.
   my $is_nonzero = $col_type =~ m/time|date/ ? \&_validate_temporal_value
                  :                             sub { return $_[1]; };

   if ( !$is_nonzero->($dbh, $val) ) {  # quasi-double-negative, sorry
      PTDEBUG && _d('Discarding zero value:', $val);
      my $sql = "SELECT $col FROM $db_tbl "
              . ($args{index_hint} ? "$args{index_hint} " : "")
              . "WHERE $col > ? AND $col IS NOT NULL "
              . ($args{where} ? "AND ($args{where}) " : '')
              . "ORDER BY $col LIMIT 1";
      PTDEBUG && _d($sql);
      my $sth = $dbh->prepare($sql);

      my $last_val = $val;
      while ( $tries-- ) {
         $sth->execute($last_val);
         my ($next_val) = $sth->fetchrow_array();
         if ( $is_nonzero->($dbh, $next_val) ) {
            PTDEBUG && _d('First non-zero value:', $next_val);
            $sth->finish();
            return $next_val;
         }
         $last_val = $next_val;
      }
      $sth->finish();
      $val = undef;  # no non-zero value found
   }

   return $val;
}

# Sub: base_count
#   Count to any number in any base with the given symbols.  E.g. if counting
#   to 10 in base 16 with symbols 0,1,2,3,4,5,6,7,8,9,a,b,c,d,e,f the result
#   is "a".  This is trival for stuff like base 16 (hex), but far less trivial
#   for arbitrary bases with arbitrary symbols like base 25 with symbols
#   B,C,D,...X,Y,Z.  For that, counting to 10 results in "L".  The base and its
#   symbols are determined by the character column.  Symbols can be non-ASCII.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   count_to - Number to count to
#   base     - Base of special system
#   symbols  - Arrayref of symbols for "numbers" in special system
#
# Returns:
#   The "number" (symbol) in the special target base system
sub base_count {
   my ( $self, %args ) = @_;
   my @required_args = qw(count_to base symbols);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($n, $base, $symbols) = @args{@required_args};

   # Can't take log of zero and the zeroth symbol in any base is the
   # zeroth symbol in any other base.
   return $symbols->[0] if $n == 0;

   my $highest_power = floor(log($n+0.00001)/log($base));
   if ( $highest_power == 0 ){
      return $symbols->[$n];
   }

   my @base_powers;
   for my $power ( 0..$highest_power ) {
      push @base_powers, ($base**$power) || 1;  
   }

   my @base_multiples;
   foreach my $base_power ( reverse @base_powers ) {
      my $multiples = floor(($n+0.00001) / $base_power);
      push @base_multiples, $multiples;
      $n -= $multiples * $base_power;
   }
   return join('', map { $symbols->[$_] } @base_multiples);
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
# End TableChunker package
# ###########################################################################
