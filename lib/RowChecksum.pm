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
# RowChecksum package
# ###########################################################################
{
# Package: RowChecksum
# RowChecksum makes checksum expressions for checksumming rows and chunks.
package RowChecksum;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use List::Util qw(max);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(OptionParser Quoter) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

# Sub: make_row_checksum
#   Make a SELECT column list to checksum a row.
#
# Required Arguments:
#   tbl  - Table ref
#
# Optional Arguments:
#   no_cols - Don't append columns to list oustide of functions.
#
# Returns:
#   Column list for SELECT
sub make_row_checksum {
   my ( $self, %args ) = @_;
   my @required_args = qw(tbl);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tbl) = @args{@required_args};

   my $o          = $self->{OptionParser};
   my $q          = $self->{Quoter};
   my $tbl_struct = $tbl->{tbl_struct};
   my $func       = $args{func} || uc($o->get('function'));
   my $cols       = $self->get_checksum_columns(%args);

   # Skip tables that have all their columns skipped; See
   # https://bugs.launchpad.net/percona-toolkit/+bug/1016131
   die "all columns are excluded by --columns or --ignore-columns"
      unless @{$cols->{select}};
      
   # Prepend columns to query, resulting in "col1, col2, FUNC(..col1, col2...)",
   # unless caller says not to.  The only caller that says not to is
   # make_chunk_checksum() which uses this row checksum as part of a larger
   # checksum.  Other callers, like TableSyncer::make_checksum_queries() call
   # this sub directly and want the actual columns.
   my $query;
   if ( !$args{no_cols} ) {
      $query = join(', ',
                  map { 
                     my $col = $_;
                     if ( $col =~ m/UNIX_TIMESTAMP/ ) {
                        # Alias col name back to itself else its name becomes
                        # "col + 0" instead of just "col".
                        my ($real_col) = /^UNIX_TIMESTAMP\((.+?)\)/;
                        $col .= " AS $real_col";
                     }
                     elsif ( $col =~ m/TRIM/ ) {
                        my ($real_col) = m/TRIM\(([^\)]+)\)/;
                        $col .= " AS $real_col";
                     }
                     $col;
                  } @{$cols->{select}})
             . ', ';
   }

   if ( uc $func ne 'FNV_64' && uc $func ne 'FNV1A_64' ) {
      my $sep = $o->get('separator') || '#';
      $sep    =~ s/'//g;
      $sep  ||= '#';

      # Add a bitmap of which nullable columns are NULL.
      my @nulls = grep { $cols->{allowed}->{$_} } @{$tbl_struct->{null_cols}};
      if ( @nulls ) {
         my $bitmap = "CONCAT("
            . join(', ', map { 'ISNULL(' . $q->quote($_) . ')' } @nulls)
            . ")";
         push @{$cols->{select}}, $bitmap;
      }

      $query .= @{$cols->{select}} > 1
              ? "$func(CONCAT_WS('$sep', " . join(', ', @{$cols->{select}}) . '))'
              : "$func($cols->{select}->[0])";
   }
   else {
      # As a special case, FNV1A_64/FNV_64 doesn't need its arguments
      # concatenated, and doesn't need a bitmap of NULLs.
      my $fnv_func = uc $func;
      $query .= "$fnv_func(" . join(', ', @{$cols->{select}}) . ')';
   }

   PTDEBUG && _d('Row checksum:', $query);
   return $query;
}

# Sub: make_chunk_checksum
#   Make a SELECT column list to checksum a chunk of rows.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   tbl - Table ref
#   dbh - dbh if func, crc_width, and crc_type aren't given
#
# Optional Arguments:
#   func      - Hash function name
#   crc_width - CRC width
#   crc_type  - CRC type
# 
# Returns:
#   Column list for SELECT
sub make_chunk_checksum {
   my ( $self, %args ) = @_;
   my @required_args = qw(tbl);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   if ( !$args{dbh} && !($args{func} && $args{crc_width} && $args{crc_type}) ) {
      die "I need a dbh argument"
   }
   my ($tbl) = @args{@required_args};
   my $o     = $self->{OptionParser};
   my $q     = $self->{Quoter};

   my %crc_args = $self->get_crc_args(%args);
   PTDEBUG && _d("Checksum strat:", Dumper(\%crc_args));

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
   my $row_checksum = $self->make_row_checksum(
      %args,
      %crc_args,
      no_cols => 1
   );
   my $crc;
   if ( $crc_args{crc_type} =~ m/int$/ ) {
      $crc = "COALESCE(LOWER(CONV(BIT_XOR(CAST($row_checksum AS UNSIGNED)), "
           . "10, 16)), 0)";
   }
   else {
      my $slices = $self->_make_xor_slices(
         row_checksum => $row_checksum,
         %crc_args,
      );
      $crc = "COALESCE(LOWER(CONCAT($slices)), 0)";
   }

   my $select = "COUNT(*) AS cnt, $crc AS crc";
   PTDEBUG && _d('Chunk checksum:', $select);
   return $select;
}

sub get_checksum_columns {
   my ($self, %args) = @_;
   my @required_args = qw(tbl);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tbl) = @args{@required_args};
   my $o     = $self->{OptionParser};
   my $q     = $self->{Quoter};

   my $trim            = $o->get('trim');
   my $float_precision = $o->get('float-precision');

   my $tbl_struct = $tbl->{tbl_struct};
   my $ignore_col = $o->get('ignore-columns') || {};
   my $all_cols   = $o->get('columns') || $tbl_struct->{cols};
   my %cols       = map { lc($_) => 1 } grep { !$ignore_col->{$_} } @$all_cols;
   my %seen;
   my @cols =
      map {
         my $type   = $tbl_struct->{type_for}->{$_};
         my $result = $q->quote($_);
         if ( $type eq 'timestamp' ) {
            $result = "UNIX_TIMESTAMP($result)";
         }
         elsif ( $float_precision && $type =~ m/float|double/ ) {
            $result = "ROUND($result, $float_precision)";
         }
         elsif ( $trim && $type =~ m/varchar/ ) {
            $result = "TRIM($result)";
         }
         $result;
      }
      grep {
         $cols{$_} && !$seen{$_}++
      }
      @{$tbl_struct->{cols}};

   return {
      select  => \@cols,
      allowed => \%cols,
   };
}

sub get_crc_args {
   my ($self, %args) = @_;
   my $func      = $args{func}     || $self->_get_hash_func(%args);
   my $crc_width = $args{crc_width}|| $self->_get_crc_width(%args, func=>$func);
   my $crc_type  = $args{crc_type} || $self->_get_crc_type(%args, func=>$func);
   my $opt_slice; 
   if ( $args{dbh} && $crc_type !~ m/int$/ ) {
      $opt_slice = $self->_optimize_xor(%args, func=>$func);
   }

   return (
      func      => $func,
      crc_width => $crc_width,
      crc_type  => $crc_type,
      opt_slice => $opt_slice,
   );
}

# Sub: _get_hash_func
#   Get the fastest available hash function.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dbh - dbh
#
# Returns:
#   Function name
sub _get_hash_func {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh) = @args{@required_args};
   my $o     = $self->{OptionParser};
   my @funcs = qw(CRC32 FNV1A_64 FNV_64 MURMUR_HASH MD5 SHA1);

   if ( my $func = $o->get('function') ) {
      unshift @funcs, $func;
   }

   my $error;
   foreach my $func ( @funcs ) {
      eval {
         my $sql = "SELECT $func('test-string')";
         PTDEBUG && _d($sql);
         $args{dbh}->do($sql);
      };
      if ( $EVAL_ERROR && $EVAL_ERROR =~ m/failed: (.*?) at \S+ line/ ) {
         $error .= qq{$func cannot be used because "$1"\n};
         PTDEBUG && _d($func, 'cannot be used because', $1);
         next;
      }
      PTDEBUG && _d('Chosen hash func:', $func);
      return $func;
   }
   die($error || 'No hash functions (CRC32, MD5, etc.) are available');
}

# Returns how wide/long, in characters, a CRC function is.
sub _get_crc_width {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh func);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $func) = @args{@required_args};

   my $crc_width = 16;
   if ( uc $func ne 'FNV_64' && uc $func ne 'FNV1A_64' ) {
      eval {
         my ($val) = $dbh->selectrow_array("SELECT $func('a')");
         $crc_width = max(16, length($val));
      };
   }
   return $crc_width;
}

# Returns a CRC function's MySQL type.
sub _get_crc_type {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh func);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $func) = @args{@required_args};

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
   return $type;
}

# Figure out which slice in a sliced BIT_XOR checksum should have the actual
# concat-columns-and-checksum, and which should just get variable references.
# Returns the slice.  I'm really not sure if this code is needed.  It always
# seems the last slice is the one that works.  But I'd rather be paranoid.
   # TODO: this function needs a hint to know when a function returns an
   # integer.  CRC32 is an example.  In these cases no optimization or slicing
   # is necessary.
sub _optimize_xor {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh func);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $func) = @args{@required_args};

   die "$func never needs BIT_XOR optimization"
      if $func =~ m/^(?:FNV1A_64|FNV_64|CRC32)$/i;

   my $opt_slice = 0;
   my $unsliced  = uc $dbh->selectall_arrayref("SELECT $func('a')")->[0]->[0];
   my $sliced    = '';
   my $start     = 1;
   my $crc_width = length($unsliced) < 16 ? 16 : length($unsliced);

   do { # Try different positions till sliced result equals non-sliced.
      PTDEBUG && _d('Trying slice', $opt_slice);
      $dbh->do(q{SET @crc := '', @cnt := 0});
      my $slices = $self->_make_xor_slices(
         row_checksum => "\@crc := $func('a')",
         crc_width    => $crc_width,
         opt_slice    => $opt_slice,
      );

      my $sql = "SELECT CONCAT($slices) AS TEST FROM (SELECT NULL) AS x";
      $sliced = ($dbh->selectrow_array($sql))[0];
      if ( $sliced ne $unsliced ) {
         PTDEBUG && _d('Slice', $opt_slice, 'does not work');
         $start += 16;
         ++$opt_slice;
      }
   } while ( $start < $crc_width && $sliced ne $unsliced );

   if ( $sliced eq $unsliced ) {
      PTDEBUG && _d('Slice', $opt_slice, 'works');
      return $opt_slice;
   }
   else {
      PTDEBUG && _d('No slice works');
      return undef;
   }
}

# Sub: _make_xor_slices
#   Make an expression that will do a bitwise XOR over a very wide integer,
#   such as that returned by SHA1, which is too large to put into BIT_XOR().
#   If an opt_slice is given, a variable is used to avoid calling row_checksum
#   multiple times.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   row_checksum - <make_row_checksum()> query
#   crc_width    - CRC width (<_get_crc_width()>
#
# Optional Arguments:
#   opt_slice - Slice number.  Use a variable to avoid calling row_checksum
#               multiple times.
#
# Returns:
#   SQL expression
sub _make_xor_slices {
   my ( $self, %args ) = @_;
   my @required_args = qw(row_checksum crc_width);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($row_checksum, $crc_width) = @args{@required_args};
   my ($opt_slice) = $args{opt_slice};

   # Create a series of slices with @crc as a placeholder.
   my @slices;
   for ( my $start = 1; $start <= $crc_width; $start += 16 ) {
      my $len = $crc_width - $start + 1;
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
      $slices[$opt_slice] =~ s/\@crc/\@crc := $row_checksum/;
   }
   else {
      map { s/\@crc/$row_checksum/ } @slices;
   }

   return join(', ', @slices);
}

# Queries the replication table for chunks that differ from the master's data.
sub find_replication_differences {
   my ($self, %args) = @_;
   my @required_args = qw(dbh repl_table);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $repl_table) = @args{@required_args};

    
   my $tries = $self->{'OptionParser'}->get('replicate-check-retries') || 1; 
   my $diffs;
   while ($tries--) {
      my $sql
         = "SELECT CONCAT(db, '.', tbl) AS `table`, "
         . "chunk, chunk_index, lower_boundary, upper_boundary, "
         . "COALESCE(this_cnt-master_cnt, 0) AS cnt_diff, "
         . "COALESCE("
         .   "this_crc <> master_crc OR ISNULL(master_crc) <> ISNULL(this_crc), 0"
         . ") AS crc_diff, this_cnt, master_cnt, this_crc, master_crc "
         . "FROM $repl_table "
         . "WHERE (master_cnt <> this_cnt OR master_crc <> this_crc "
         .        "OR ISNULL(master_crc) <> ISNULL(this_crc)) "
         . ($args{where} ? " AND ($args{where})" : "");
      PTDEBUG && _d($sql);
      $diffs = $dbh->selectall_arrayref($sql, { Slice => {} });
      if (!@$diffs || !$tries) { # if no differences are found OR we are out of tries left...
         last;                   # get out now
      }
      sleep 1;            
   }
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
# End RowChecksum package
# ###########################################################################
