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
# TableChecksum package
# ###########################################################################
{
# Package: TableChecksum
# TableChecksum checksums tables.
package TableChecksum;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use List::Util qw(max);

# BXT_XOR is actually faster than ACCUM as long as the user-variable
# optimization can be used.  I've never seen a case where it can't be.
our %ALGOS = (
   CHECKSUM => { pref => 0, hash => 0 },
   BIT_XOR  => { pref => 2, hash => 1 },
   ACCUM    => { pref => 3, hash => 1 },
);

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(Quoter) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

# Perl implementation of CRC32, ripped off from Digest::Crc32.  The results
# ought to match what you get from any standard CRC32 implementation, such as
# that inside MySQL.
sub crc32 {
   my ( $self, $string ) = @_;
   my $poly = 0xEDB88320;
   my $crc  = 0xFFFFFFFF;
   foreach my $char ( split(//, $string) ) {
      my $comp = ($crc ^ ord($char)) & 0xFF;
      for ( 1 .. 8 ) {
         $comp = $comp & 1 ? $poly ^ ($comp >> 1) : $comp >> 1;
      }
      $crc = (($crc >> 8) & 0x00FFFFFF) ^ $comp;
   }
   return $crc ^ 0xFFFFFFFF;
}

# Returns how wide/long, in characters, a CRC function is.
sub get_crc_wid {
   my ( $self, $dbh, $func ) = @_;
   my $crc_wid = 16;
   if ( uc $func ne 'FNV_64' && uc $func ne 'FNV1A_64' ) {
      eval {
         my ($val) = $dbh->selectrow_array("SELECT $func('a')");
         $crc_wid = max(16, length($val));
      };
   }
   return $crc_wid;
}

# Returns a CRC function's MySQL type as a list of (type, length).
sub get_crc_type {
   my ( $self, $dbh, $func ) = @_;
   my $type   = '';
   my $length = 0;
   my $sql    = "SELECT $func('a')";
   my $sth    = $dbh->prepare($sql);
   eval {
      $sth->execute();
      $type   = $sth->{mysql_type_name}->[0];
      $length = $sth->{mysql_length}->[0];
      PTDEBUG && _d($sql, $type, $length);
      if ( $type eq 'bigint' && $length < 20 ) {
         $type = 'int';
      }
   };
   $sth->finish;
   PTDEBUG && _d('crc_type:', $type, 'length:', $length);
   return ($type, $length);
}

# Arguments:
#   algorithm   (optional) One of CHECKSUM, ACCUM, BIT_XOR
#   dbh         DB handle
#   where       bool: whether user wants a WHERE clause applied
#   chunk       bool: whether user wants to checksum in chunks
#   replicate   bool: whether user wants to do via replication
#   count       bool: whether user wants a row count too
sub best_algorithm {
   my ( $self, %args ) = @_;
   my ( $alg, $dbh ) = @args{ qw(algorithm dbh) };
   my @choices = sort { $ALGOS{$a}->{pref} <=> $ALGOS{$b}->{pref} } keys %ALGOS;
   die "Invalid checksum algorithm $alg"
      if $alg && !$ALGOS{$alg};

   # CHECKSUM is eliminated by lots of things...
   if (
      $args{where} || $args{chunk}        # CHECKSUM does whole table
      || $args{replicate})                # CHECKSUM can't do INSERT.. SELECT
   {
      PTDEBUG && _d('Cannot use CHECKSUM algorithm');
      @choices = grep { $_ ne 'CHECKSUM' } @choices;
   }


   # Choose the best (fastest) among the remaining choices.
   if ( $alg && grep { $_ eq $alg } @choices ) {
      # Honor explicit choices.
      PTDEBUG && _d('User requested', $alg, 'algorithm');
      return $alg;
   }

   # If the user wants a count, prefer something other than CHECKSUM, because it
   # requires an extra query for the count.
   if ( $args{count} && grep { $_ ne 'CHECKSUM' } @choices ) {
      PTDEBUG && _d('Not using CHECKSUM algorithm because COUNT desired');
      @choices = grep { $_ ne 'CHECKSUM' } @choices;
   }

   PTDEBUG && _d('Algorithms, in order:', @choices);
   return $choices[0];
}

sub is_hash_algorithm {
   my ( $self, $algorithm ) = @_;
   return $ALGOS{$algorithm} && $ALGOS{$algorithm}->{hash};
}

# Picks a hash function, in order of speed.
# Arguments:
#   * dbh
#   * function  (optional) Preferred function: SHA1, MD5, etc.
sub choose_hash_func {
   my ( $self, %args ) = @_;
   my @funcs = qw(CRC32 FNV1A_64 FNV_64 MD5 SHA1);
   if ( $args{function} ) {
      unshift @funcs, $args{function};
   }
   my ($result, $error);
   do {
      my $func;
      eval {
         $func = shift(@funcs);
         my $sql = "SELECT $func('test-string')";
         PTDEBUG && _d($sql);
         $args{dbh}->do($sql);
         $result = $func;
      };
      if ( $EVAL_ERROR && $EVAL_ERROR =~ m/failed: (.*?) at \S+ line/ ) {
         $error .= qq{$func cannot be used because "$1"\n};
         PTDEBUG && _d($func, 'cannot be used because', $1);
      }
   } while ( @funcs && !$result );

   die $error unless $result;
   PTDEBUG && _d('Chosen hash func:', $result);
   return $result;
}

# Figure out which slice in a sliced BIT_XOR checksum should have the actual
# concat-columns-and-checksum, and which should just get variable references.
# Returns the slice.  I'm really not sure if this code is needed.  It always
# seems the last slice is the one that works.  But I'd rather be paranoid.
   # TODO: this function needs a hint to know when a function returns an
   # integer.  CRC32 is an example.  In these cases no optimization or slicing
   # is necessary.
sub optimize_xor {
   my ( $self, %args ) = @_;
   my ($dbh, $func) = @args{qw(dbh function)};

   die "$func never needs the BIT_XOR optimization"
      if $func =~ m/^(?:FNV1A_64|FNV_64|CRC32)$/i;

   my $opt_slice = 0;
   my $unsliced  = uc $dbh->selectall_arrayref("SELECT $func('a')")->[0]->[0];
   my $sliced    = '';
   my $start     = 1;
   my $crc_wid   = length($unsliced) < 16 ? 16 : length($unsliced);

   do { # Try different positions till sliced result equals non-sliced.
      PTDEBUG && _d('Trying slice', $opt_slice);
      $dbh->do(q{SET @crc := '', @cnt := 0});
      my $slices = $self->make_xor_slices(
         query     => "\@crc := $func('a')",
         crc_wid   => $crc_wid,
         opt_slice => $opt_slice,
      );

      my $sql = "SELECT CONCAT($slices) AS TEST FROM (SELECT NULL) AS x";
      $sliced = ($dbh->selectrow_array($sql))[0];
      if ( $sliced ne $unsliced ) {
         PTDEBUG && _d('Slice', $opt_slice, 'does not work');
         $start += 16;
         ++$opt_slice;
      }
   } while ( $start < $crc_wid && $sliced ne $unsliced );

   if ( $sliced eq $unsliced ) {
      PTDEBUG && _d('Slice', $opt_slice, 'works');
      return $opt_slice;
   }
   else {
      PTDEBUG && _d('No slice works');
      return undef;
   }
}

# Returns an expression that will do a bitwise XOR over a very wide integer,
# such as that returned by SHA1, which is too large to just put into BIT_XOR().
# $query is an expression that returns a row's checksum, $crc_wid is the width
# of that expression in characters.  If the opt_slice argument is given, use a
# variable to avoid calling the $query expression multiple times.  The variable
# goes in slice $opt_slice.
# Arguments:
#   * query
#   * crc_wid
#   * opt_slice  (optional)
sub make_xor_slices {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(query crc_wid) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ( $query, $crc_wid, $opt_slice ) = @args{qw(query crc_wid opt_slice)};

   # Create a series of slices with @crc as a placeholder.
   my @slices;
   for ( my $start = 1; $start <= $crc_wid; $start += 16 ) {
      my $len = $crc_wid - $start + 1;
      if ( $len > 16 ) {
         $len = 16;
      }
      push @slices,
         "LPAD(CONV(BIT_XOR("
         . "CAST(CONV(SUBSTRING(\@crc, $start, $len), 16, 10) AS UNSIGNED))"
         . ", 10, 16), $len, '0')";
   }

   # Replace the placeholder with the expression.  If specified, add a
   # user-variable optimization so the expression goes in only one of the
   # slices.  This optimization relies on @crc being '' when the query begins.
   if ( defined $opt_slice && $opt_slice < @slices ) {
      $slices[$opt_slice] =~ s/\@crc/\@crc := $query/;
   }
   else {
      map { s/\@crc/$query/ } @slices;
   }

   return join(', ', @slices);
}

# Generates a checksum query for a given table.  Arguments:
# *   tbl_struct  Struct as returned by TableParser::parse()
# *   function    SHA1, MD5, etc
# *   sep         (optional) Separator for CONCAT_WS(); default #
# *   cols        (optional) arrayref of columns to checksum
# *   trim        (optional) wrap VARCHAR cols in TRIM() for v4/v5 compatibility
# *   ignorecols  (optional) arrayref of columns to exclude from checksum
sub make_row_checksum {
   my ( $self, %args ) = @_;
   my ( $tbl_struct, $func ) = @args{ qw(tbl_struct function) };
   my $q = $self->{Quoter};

   my $sep = $args{sep} || '#';
   $sep =~ s/'//g;
   $sep ||= '#';

   # This allows a simpler grep when building %cols below.
   my $ignorecols = $args{ignorecols} || {};

   # Generate the expression that will turn a row into a checksum.
   # Choose columns.  Normalize query results: make FLOAT and TIMESTAMP
   # stringify uniformly.
   my %cols = map { lc($_) => 1 }
              grep { !exists $ignorecols->{$_} }
              ($args{cols} ? @{$args{cols}} : @{$tbl_struct->{cols}});
   my %seen;
   my @cols =
      map {
         my $type = $tbl_struct->{type_for}->{$_};
         my $result = $q->quote($_);
         if ( $type eq 'timestamp' ) {
            $result .= ' + 0';
         }
         elsif ( $args{float_precision} && $type =~ m/float|double/ ) {
            $result = "ROUND($result, $args{float_precision})";
         }
         elsif ( $args{trim} && $type =~ m/varchar/ ) {
            $result = "TRIM($result)";
         }
         $result;
      }
      grep {
         $cols{$_} && !$seen{$_}++
      }
      @{$tbl_struct->{cols}};

   # Prepend columns to query, resulting in "col1, col2, FUNC(..col1, col2...)",
   # unless caller says not to.  The only caller that says not to is
   # make_checksum_query() which uses this row checksum as part of a larger
   # checksum.  Other callers, like TableSyncer::make_checksum_queries() call
   # this sub directly and want the actual columns.
   my $query;
   if ( !$args{no_cols} ) {
      $query = join(', ',
                  map { 
                     my $col = $_;
                     if ( $col =~ m/\+ 0/ ) {
                        # Alias col name back to itself else its name becomes
                        # "col + 0" instead of just "col".
                        my ($real_col) = /^(\S+)/;
                        $col .= " AS $real_col";
                     }
                     elsif ( $col =~ m/TRIM/ ) {
                        my ($real_col) = m/TRIM\(([^\)]+)\)/;
                        $col .= " AS $real_col";
                     }
                     $col;
                  } @cols)
             . ', ';
   }

   if ( uc $func ne 'FNV_64' && uc $func ne 'FNV1A_64' ) {
      # Add a bitmap of which nullable columns are NULL.
      my @nulls = grep { $cols{$_} } @{$tbl_struct->{null_cols}};
      if ( @nulls ) {
         my $bitmap = "CONCAT("
            . join(', ', map { 'ISNULL(' . $q->quote($_) . ')' } @nulls)
            . ")";
         push @cols, $bitmap;
      }

      $query .= @cols > 1
              ? "$func(CONCAT_WS('$sep', " . join(', ', @cols) . '))'
              : "$func($cols[0])";
   }
   else {
      # As a special case, FNV1A_64/FNV_64 doesn't need its arguments
      # concatenated, and doesn't need a bitmap of NULLs.
      my $fnv_func = uc $func;
      $query .= "$fnv_func(" . join(', ', @cols) . ')';
   }

   return $query;
}

# Generates a checksum query for a given table.  Arguments:
# *   db          Database name
# *   tbl         Table name
# *   tbl_struct  Struct as returned by TableParser::parse()
# *   algorithm   Any of @ALGOS
# *   function    (optional) SHA1, MD5, etc
# *   crc_wid     Width of the string returned by function
# *   crc_type    Type of function's result
# *   opt_slice   (optional) Which slice gets opt_xor (see make_xor_slices()).
# *   cols        (optional) see make_row_checksum()
# *   sep         (optional) see make_row_checksum()
# *   replicate   (optional) generate query to REPLACE into this table.
# *   trim        (optional) see make_row_checksum().
# *   buffer      (optional) Adds SQL_BUFFER_RESULT.
sub make_checksum_query {
   my ( $self, %args ) = @_;
   my @required_args = qw(db tbl tbl_struct algorithm crc_wid crc_type);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ( $db, $tbl, $tbl_struct, $algorithm,
        $crc_wid, $crc_type) = @args{@required_args};
   my $func = $args{function};
   my $q = $self->{Quoter};
   my $result;

   die "Invalid or missing checksum algorithm"
      unless $algorithm && $ALGOS{$algorithm};

   if ( $algorithm eq 'CHECKSUM' ) {
      return "CHECKSUM TABLE " . $q->quote($db, $tbl);
   }

   my $expr = $self->make_row_checksum(%args, no_cols=>1);

   if ( $algorithm eq 'BIT_XOR' ) {
      # This checksum algorithm concatenates the columns in each row and
      # checksums them, then slices this checksum up into 16-character chunks.
      # It then converts them BIGINTs with the CONV() function, and then
      # groupwise XORs them to produce an order-independent checksum of the
      # slice over all the rows.  It then converts these back to base 16 and
      # puts them back together.  The effect is the same as XORing a very wide
      # (32 characters = 128 bits for MD5, and SHA1 is even larger) unsigned
      # integer over all the rows.
      #
      # As a special case, integer functions do not need to be sliced.  They
      # can be fed right into BIT_XOR after a cast to UNSIGNED.
      if ( $crc_type =~ m/int$/ ) {
         $result = "COALESCE(LOWER(CONV(BIT_XOR(CAST($expr AS UNSIGNED)), 10, 16)), 0) AS crc ";
      }
      else {
         my $slices = $self->make_xor_slices( query => $expr, %args );
         $result = "COALESCE(LOWER(CONCAT($slices)), 0) AS crc ";
      }
   }
   else {
      # Use an accumulator variable.  This query relies on @crc being '', and
      # @cnt being 0 when it begins.  It checksums each row, appends it to the
      # running checksum, and checksums the two together.  In this way it acts
      # as an accumulator for all the rows.  It then prepends a steadily
      # increasing number to the left, left-padded with zeroes, so each checksum
      # taken is stringwise greater than the last.  In this way the MAX()
      # function can be used to return the last checksum calculated.  @cnt is
      # not used for a row count, it is only used to make MAX() work correctly.
      #
      # As a special case, int funcs must be converted to base 16 so it's a
      # predictable width (it's also a shorter string, but that's not really
      # important).
      #
      # On MySQL 4.0 and older, crc is NULL/undef if no rows are selected.
      # We COALESCE to avoid having to check that crc is defined; see
      # http://code.google.com/p/maatkit/issues/detail?id=672
      if ( $crc_type =~ m/int$/ ) {
         $result = "COALESCE(RIGHT(MAX("
            . "\@crc := CONCAT(LPAD(\@cnt := \@cnt + 1, 16, '0'), "
            . "CONV(CAST($func(CONCAT(\@crc, $expr)) AS UNSIGNED), 10, 16))"
            . "), $crc_wid), 0) AS crc ";
      }
      else {
         $result = "COALESCE(RIGHT(MAX("
            . "\@crc := CONCAT(LPAD(\@cnt := \@cnt + 1, 16, '0'), "
            . "$func(CONCAT(\@crc, $expr)))"
            . "), $crc_wid), 0) AS crc ";
      }
   }
   if ( $args{replicate} ) {
      $result = "REPLACE /*PROGRESS_COMMENT*/ INTO $args{replicate} "
         . "(db, tbl, chunk, boundaries, this_cnt, this_crc) "
         . "SELECT ?, ?, /*CHUNK_NUM*/ ?, COUNT(*) AS cnt, $result";
   }
   else {
      $result = "SELECT "
         . ($args{buffer} ? 'SQL_BUFFER_RESULT ' : '')
         . "/*PROGRESS_COMMENT*//*CHUNK_NUM*/ COUNT(*) AS cnt, $result";
   }
   return $result . "FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/";
}

# Queries the replication table for chunks that differ from the master's data.
sub find_replication_differences {
   my ( $self, $dbh, $table ) = @_;

   my $sql
      = "SELECT db, tbl, CONCAT(db, '.', tbl) AS `table`, "
      . "chunk, chunk_index, lower_boundary, upper_boundary, "
      . "COALESCE(this_cnt-master_cnt, 0) AS cnt_diff, "
      . "COALESCE("
      .   "this_crc <> master_crc OR ISNULL(master_crc) <> ISNULL(this_crc), 0"
      . ") AS crc_diff, this_cnt, master_cnt, this_crc, master_crc "
      . "FROM $table "
      . "WHERE master_cnt <> this_cnt OR master_crc <> this_crc "
      . "OR ISNULL(master_crc) <> ISNULL(this_crc)";
   PTDEBUG && _d($sql);
   my $diffs = $dbh->selectall_arrayref($sql, { Slice => {} });
   return $diffs;
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
# End TableChecksum package
# ###########################################################################
