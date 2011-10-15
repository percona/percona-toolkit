# This program is copyright 2011 Percona Inc.
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
# NibbleIterator package
# ###########################################################################
{
# Package: NibbleIterator
# NibbleIterator nibbles tables.
package NibbleIterator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# Sub: new
#
# Required Arguments:
#   cxn          - <Cxn> object
#   tbl          - Standard tbl ref
#   chunk_size   - Number of rows to nibble per chunk
#   OptionParser - <OptionParser> object
#   TableNibbler - <TableNibbler> object
#   TableParser  - <TableParser> object
#   Quoter       - <Quoter> object
#
# Optional Arguments:
#   chunk_index - Index to use for nibbling
#   one_nibble  - Allow one-chunk tables (default yes)
#   where       - WHERE clause
#
# Returns:
#  NibbleIterator object 
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(Cxn tbl chunk_size OptionParser Quoter TableNibbler TableParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($cxn, $tbl, $chunk_size, $o, $q) = @args{@required_args};

   my ($row_est, $mysql_index) = _get_row_estimate(%args);
   my $one_nibble = !defined $args{one_nibble} || $args{one_nibble}
                  ? $row_est <= $chunk_size * $o->get('chunk-size-limit')
                  : 0;
   MKDEBUG && _d('One nibble:', $one_nibble ? 'yes' : 'no');

   # Get an index to nibble by.  We'll order rows by the index's columns.
   my $index = _find_best_index(%args, mysql_index => $mysql_index);
   if ( !$index && !$one_nibble ) {
      die "There is no good index and the table is oversized.";
   }

   my $where = $o->get('where');
   my $self;
   if ( $one_nibble ) {
      my $tbl_struct = $tbl->{tbl_struct};
      my $ignore_col = $o->get('ignore-columns') || {};
      my $all_cols   = $o->get('columns') || $tbl_struct->{cols};
      my @cols       = grep { !$ignore_col->{$_} } @$all_cols;

      # If the chunk size is >= number of rows in table, then we don't
      # need to chunk; we can just select all rows, in order, at once.
      my $nibble_sql
         = ($args{dms} ? "$args{dms} " : "SELECT ")
         . ($args{select} ? $args{select}
                          : join(', ', map { $q->quote($_) } @cols))
         . " FROM " . $q->quote(@{$tbl}{qw(db tbl)})
         . ($where ? " AND ($where)" : '')
         . " /*checksum table*/";
      MKDEBUG && _d('One nibble statement:', $nibble_sql);

      my $explain_nibble_sql
         = "EXPLAIN SELECT "
         . ($args{select} ? $args{select}
                          : join(', ', map { $q->quote($_) } @cols))
         . " FROM " . $q->quote(@{$tbl}{qw(db tbl)})
         . ($where ? " AND ($where)" : '')
         . " /*explain checksum table*/";
      MKDEBUG && _d('Explain one nibble statement:', $explain_nibble_sql);

      $self = {
         %args,
         one_nibble         => 1,
         limit              => 0,
         nibble_sql         => $nibble_sql,
         explain_nibble_sql => $explain_nibble_sql,
      };
   }
   else {
      my $index_cols = $tbl->{tbl_struct}->{keys}->{$index}->{cols};

      # Figure out how to nibble the table with the index.
      my $asc = $args{TableNibbler}->generate_asc_stmt(
         %args,
         tbl_struct => $tbl->{tbl_struct},
         index      => $index,
         asc_only   => 1,
      );
      MKDEBUG && _d('Ascend params:', Dumper($asc));

      # Make SQL statements, prepared on first call to next().  FROM and
      # ORDER BY are the same for all statements.  FORCE IDNEX and ORDER BY
      # are needed to ensure deterministic nibbling.
      my $from     = $q->quote(@{$tbl}{qw(db tbl)}) . " FORCE INDEX(`$index`)";
      my $order_by = join(', ', map {$q->quote($_)} @{$index_cols});

      # These statements are only executed once, so they don't use sths.
      my $first_lb_sql
         = "SELECT /*!40001 SQL_NO_CACHE */ "
         . join(', ', map { $q->quote($_) } @{$asc->{scols}})
         . " FROM $from"
         . ($where ? " WHERE $where" : '')
         . " ORDER BY $order_by"
         . " LIMIT 1"
         . " /*first lower boundary*/";
      MKDEBUG && _d('First lower boundary statement:', $first_lb_sql);

      my $last_ub_sql
         = "SELECT /*!40001 SQL_NO_CACHE */ "
         . join(', ', map { $q->quote($_) } @{$asc->{scols}})
         . " FROM $from"
         . ($where ? " WHERE $where" : '')
         . " ORDER BY "
         . join(' DESC, ', map {$q->quote($_)} @{$index_cols}) . ' DESC'
         . " LIMIT 1"
         . " /*last upper boundary*/";
      MKDEBUG && _d('Last upper boundary statement:', $last_ub_sql);

      # Nibbles are inclusive, so for a..z, the nibbles are: a-e, f-j, k-o, p-t,
      # u-y, and z.  This complicates getting the next upper boundary because
      # if we use either (col >= lb AND col < ub) or (col > lb AND col <= ub)
      # in nibble_sql (below), then that fails for either the last or first
      # nibble respectively.  E.g. (col >= z AND col < z) doesn't work, nor
      # does (col > a AND col <= e).  Hence the fancy LIMIT 2 which returns
      # the upper boundary for the current nibble *and* the lower boundary
      # for the next nibble.  See _next_boundaries().
      my $ub_sql
         = "SELECT /*!40001 SQL_NO_CACHE */ "
         . join(', ', map { $q->quote($_) } @{$asc->{scols}})
         . " FROM $from"
         . " WHERE " . $asc->{boundaries}->{'>='}
                     . ($where ? " AND ($where)" : '')
         . " ORDER BY $order_by"
         . " LIMIT ?, 2"
         . " /*next chunk boundary*/";
      MKDEBUG && _d('Upper boundary statement:', $ub_sql);

      # This statement does the actual nibbling work; its rows are returned
      # to the caller via next().
      my $nibble_sql
         = ($args{dms} ? "$args{dms} " : "SELECT ")
         . ($args{select} ? $args{select}
                          : join(', ', map { $q->quote($_) } @{$asc->{cols}}))
         . " FROM $from"
         . " WHERE " . $asc->{boundaries}->{'>='}  # lower boundary
         . " AND "   . $asc->{boundaries}->{'<='}  # upper boundary
         . ($where ? " AND ($where)" : '')
         . " ORDER BY $order_by"
         . " /*checksum chunk*/";
      MKDEBUG && _d('Nibble statement:', $nibble_sql);

      my $explain_nibble_sql 
         = "EXPLAIN SELECT "
         . ($args{select} ? $args{select}
                          : join(', ', map { $q->quote($_) } @{$asc->{cols}}))
         . " FROM $from"
         . " WHERE " . $asc->{boundaries}->{'>='}  # lower boundary
         . " AND "   . $asc->{boundaries}->{'<='}  # upper boundary
         . ($where ? " AND ($where)" : '')
         . " ORDER BY $order_by"
         . " /*explain checksum chunk*/";
      MKDEBUG && _d('Explain nibble statement:', $explain_nibble_sql);

      my $limit = $chunk_size - 1;
      MKDEBUG && _d('Initial chunk size (LIMIT):', $limit);

      $self = {
         %args,
         index              => $index,
         limit              => $limit,
         first_lb_sql       => $first_lb_sql,
         last_ub_sql        => $last_ub_sql,
         ub_sql             => $ub_sql,
         nibble_sql         => $nibble_sql,
         explain_ub_sql     => "EXPLAIN $ub_sql",
         explain_nibble_sql => $explain_nibble_sql,
         sql                => {
            columns    => $asc->{scols},
            from       => $from,
            where      => $where,
            boundaries => $asc->{boundaries},
            order_by   => $order_by,
         },
      };
   }

   $self->{row_est}   = $row_est;
   $self->{nibbleno}  = 0;
   $self->{have_rows} = 0;
   $self->{rowno}     = 0;

   return bless $self, $class;
}

sub next {
   my ($self) = @_;

   my %callback_args = (
      Cxn            => $self->{Cxn},
      tbl            => $self->{tbl},
      NibbleIterator => $self,
   );

   # First call, init everything.  This could be done in new(), but
   # all work is delayed until actually needed.
   if ($self->{nibbleno} == 0) {
      $self->_prepare_sths();
      $self->_get_bounds();
      if ( my $callback = $self->{callbacks}->{init} ) {
         my $oktonibble = $callback->(%callback_args);
         MKDEBUG && _d('init callback returned', $oktonibble);
         if ( !$oktonibble ) {
            $self->{no_more_boundaries} = 1;
            return;
         }
      }
   }

   # If there's another nibble, fetch the rows within it.
   NIBBLE:
   while ( $self->{have_rows} || $self->_next_boundaries() ) {
      # If no rows, then we just got the next boundaries, which start
      # the next nibble.
      if ( !$self->{have_rows} ) {
         $self->{nibbleno}++;
         MKDEBUG && _d($self->{nibble_sth}->{Statement}, 'params:',
            join(', ', (@{$self->{lower}}, @{$self->{upper}})));
         if ( my $callback = $self->{callbacks}->{exec_nibble} ) {
            $self->{have_rows} = $callback->(%callback_args);
         }
         else {
            $self->{nibble_sth}->execute(@{$self->{lower}}, @{$self->{upper}});
            $self->{have_rows} = $self->{nibble_sth}->rows();
         }
         MKDEBUG && _d($self->{have_rows}, 'rows in nibble', $self->{nibbleno});
      }

      # Return rows in this nibble.
      if ( $self->{have_rows} ) {
         # Return rows in nibble.  sth->{Active} is always true with
         # DBD::mysql v3, so we track the status manually.
         my $row = $self->{nibble_sth}->fetchrow_arrayref();
         if ( $row ) {
            $self->{rowno}++;
            MKDEBUG && _d('Row', $self->{rowno}, 'in nibble',$self->{nibbleno});
            # fetchrow_arraryref re-uses an internal arrayref, so we must copy.
            return [ @$row ];
         }
      }

      MKDEBUG && _d('No rows in nibble or nibble skipped');
      if ( my $callback = $self->{callbacks}->{after_nibble} ) {
         $callback->(%callback_args);
      }
      $self->{rowno}     = 0;
      $self->{have_rows} = 0;
   }

   MKDEBUG && _d('Done nibbling');
   if ( my $callback = $self->{callbacks}->{done} ) {
      $callback->(%callback_args);
   }

   return;
}

sub nibble_number {
   my ($self) = @_;
   return $self->{nibbleno};
}

sub set_nibble_number {
   my ($self, $n) = @_;
   die "I need a number" unless $n;
   $self->{nibbleno} = $n;
   MKDEBUG && _d('Set new nibble number:', $n);
   return;
}

sub nibble_index {
   my ($self) = @_;
   return $self->{index};
}

sub statements {
   my ($self) = @_;
   return {
      nibble                 => $self->{nibble_sth},
      explain_nibble         => $self->{explain_nibble_sth},
      upper_boundary         => $self->{ub_sth},
      explain_upper_boundary => $self->{explain_ub_sth},
   }
}

sub boundaries {
   my ($self) = @_;
   return {
      lower       => $self->{lower},
      upper       => $self->{upper},
      next_lower  => $self->{next_lower},
      last_upper  => $self->{last_upper},
   };
}

sub set_boundary {
   my ($self, $boundary, $values) = @_;
   die "I need a boundary parameter"
      unless $boundary;
   die "Invalid boundary: $boundary"
      unless $boundary =~ m/^(?:lower|upper|next_lower|last_upper)$/;
   die "I need a values arrayref parameter"
      unless $values && ref $values eq 'ARRAY';
   $self->{$boundary} = $values;
   MKDEBUG && _d('Set new', $boundary, 'boundary:', Dumper($values));
   return;
}

sub one_nibble {
   my ($self) = @_;
   return $self->{one_nibble};
}

sub chunk_size {
   my ($self) = @_;
   return $self->{limit};
}

sub set_chunk_size {
   my ($self, $limit) = @_;
   return if $self->{one_nibble};
   die "Chunk size must be > 0" unless $limit;
   $self->{limit} = $limit - 1;
   MKDEBUG && _d('Set new chunk size (LIMIT):', $limit);
   return;
}

sub sql {
   my ($self) = @_;
   return $self->{sql};
}

sub more_boundaries {
   my ($self) = @_;
   return !$self->{no_more_boundaries};
}

sub row_estimate {
   my ($self) = @_;
   return $self->{row_est};
}

sub _find_best_index {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl TableParser);
   my ($cxn, $tbl, $tp) = @args{@required_args};
   my $tbl_struct = $tbl->{tbl_struct};
   my $indexes    = $tbl_struct->{keys};

   my $want_index = $args{chunk_index};
   if ( $want_index ) {
      MKDEBUG && _d('User wants to use index', $want_index);
      if ( !exists $indexes->{$want_index} ) {
         MKDEBUG && _d('Cannot use user index because it does not exist');
         $want_index = undef;
      }
   }

   if ( !$want_index && $args{mysql_index} ) {
      MKDEBUG && _d('MySQL wants to use index', $args{mysql_index});
      $want_index = $args{mysql_index};
   }

   my $best_index;
   my @possible_indexes;
   if ( $want_index ) {
      if ( $indexes->{$want_index}->{is_unique} ) {
         MKDEBUG && _d('Will use wanted index');
         $best_index = $want_index;
      }
      else {
         MKDEBUG && _d('Wanted index is a possible index');
         push @possible_indexes, $want_index;
      }
   }
   else {
      MKDEBUG && _d('Auto-selecting best index');
      foreach my $index ( $tp->sort_indexes($tbl_struct) ) {
         if ( $index eq 'PRIMARY' || $indexes->{$index}->{is_unique} ) {
            $best_index = $index;
            last;
         }
         else {
            push @possible_indexes, $index;
         }
      }
   }

   if ( !$best_index && @possible_indexes ) {
      MKDEBUG && _d('No PRIMARY or unique indexes;',
         'will use index with highest cardinality');
      foreach my $index ( @possible_indexes ) {
         $indexes->{$index}->{cardinality} = _get_index_cardinality(
            %args,
            index => $index,
         );
      }
      @possible_indexes = sort {
         # Prefer the index with the highest cardinality.
         my $cmp
            = $indexes->{$b}->{cardinality} <=> $indexes->{$b}->{cardinality};
         if ( $cmp == 0 ) {
            # Indexes have the same cardinality; prefer the one with
            # more columns.
            $cmp = scalar @{$indexes->{$b}->{cols}}
               <=> scalar @{$indexes->{$a}->{cols}};
         }
         $cmp;
      } @possible_indexes;
      $best_index = $possible_indexes[0];
   }

   MKDEBUG && _d('Best index:', $best_index);
   return $best_index;
}

sub _get_index_cardinality {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl index Quoter);
   my ($cxn, $tbl, $index, $q) = @args{@required_args};

   my $sql = "SHOW INDEXES FROM " . $q->quote(@{$tbl}{qw(db tbl)})
           . " WHERE Key_name = '$index'";
   MKDEBUG && _d($sql);
   my $cardinality = 1;
   my $rows = $cxn->dbh()->selectall_hashref($sql, 'key_name');
   foreach my $row ( values %$rows ) {
      $cardinality *= $row->{cardinality} if $row->{cardinality};
   }
   MKDEBUG && _d('Index', $index, 'cardinality:', $cardinality);
   return $cardinality;
}

sub _get_row_estimate {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl OptionParser TableParser Quoter);
   my ($cxn, $tbl, $o, $tp, $q) = @args{@required_args};

   if ( my $where = $o->get('where') ) {
      MKDEBUG && _d('WHERE clause, using explain plan for row estimate');
      my $table = $q->quote(@{$tbl}{qw(db tbl)});
      my $sql   = "EXPLAIN SELECT COUNT(*) FROM $table WHERE $where";
      MKDEBUG && _d($sql);
      my $expl = $cxn->dbh()->selectrow_hashref($sql);
      MKDEBUG && _d(Dumper($expl));
      return ($expl->{rows} || 0), $expl->{key};
   }
   else {
      MKDEBUG && _d('No WHERE clause, using table status for row estimate');
      return $tbl->{tbl_status}->{rows} || 0;
   }
}

sub _prepare_sths {
   my ($self) = @_;
   MKDEBUG && _d('Preparing statement handles');

   my $dbh = $self->{Cxn}->dbh();

   $self->{nibble_sth}         = $dbh->prepare($self->{nibble_sql});
   $self->{explain_nibble_sth} = $dbh->prepare($self->{explain_nibble_sql});

   if ( !$self->{one_nibble} ) {
      $self->{ub_sth} = $dbh->prepare($self->{ub_sql});
      $self->{explain_ub_sth} = $dbh->prepare($self->{explain_ub_sql});
   }

   return;
}

sub _get_bounds { 
   my ($self) = @_;
   return if $self->{one_nibble};

   my $dbh = $self->{Cxn}->dbh();

   $self->{next_lower} = $dbh->selectrow_arrayref($self->{first_lb_sql});
   MKDEBUG && _d('First lower boundary:', Dumper($self->{next_lower}));

   $self->{last_upper} = $dbh->selectrow_arrayref($self->{last_ub_sql});
   MKDEBUG && _d('Last upper boundary:', Dumper($self->{last_upper}));

   return;
}

sub _next_boundaries {
   my ($self) = @_;

   if ( $self->{no_more_boundaries} ) {
      MKDEBUG && _d('No more boundaries');
      return; # stop nibbling
   }

   if ( $self->{one_nibble} ) {
      $self->{lower} = $self->{upper} = [];
      $self->{no_more_boundaries} = 1;  # for next call
      return 1; # continue nibbling
   }

   # Detect infinite loops.  If the lower boundary we just nibbled from
   # is identical to the next lower boundary, then this next nibble won't
   # go anywhere, so to speak, unless perhaps the chunk size has changed
   # which will cause us to nibble further ahead and maybe get a new lower
   # boundary that isn't identical, but we can't detect this, and in any
   # case, if there's one infinite loop there will probably be others.
   if ( $self->identical_boundaries($self->{lower}, $self->{next_lower}) ) {
      MKDEBUG && _d('Infinite loop detected');
      my $tbl     = $self->{tbl};
      my $index   = $tbl->{tbl_struct}->{keys}->{$self->{index}};
      my $n_cols  = scalar @{$index->{cols}};
      my $chunkno = $self->{nibbleno};
      die "Possible infinite loop detected!  "
         . "The lower boundary for chunk $chunkno is "
         . "<" . join(', ', @{$self->{lower}}) . "> and the lower "
         . "boundary for chunk " . ($chunkno + 1) . " is also "
         . "<" . join(', ', @{$self->{next_lower}}) . ">.  "
         . "This usually happens when using a non-unique single "
         . "column index.  The current chunk index for table "
         . "$tbl->{db}.$tbl->{tbl} is $self->{index} which is"
         . ($index->{is_unique} ? '' : ' not') . " unique and covers "
         . ($n_cols > 1 ? "$n_cols columns" : "1 column") . ".\n";
   }
   $self->{lower} = $self->{next_lower};

   if ( my $callback = $self->{callbacks}->{next_boundaries} ) {
      my $oktonibble = $callback->(
         Cxn            => $self->{Cxn},
         tbl            => $self->{tbl},
         NibbleIterator => $self,
      );
      MKDEBUG && _d('next_boundaries callback returned', $oktonibble);
      if ( !$oktonibble ) {
         $self->{no_more_boundaries} = 1;
         return; # stop nibbling
      }
   }

   MKDEBUG && _d($self->{ub_sth}->{Statement}, 'params:',
      join(', ', @{$self->{lower}}), $self->{limit});
   $self->{ub_sth}->execute(@{$self->{lower}}, $self->{limit});
   my $boundary = $self->{ub_sth}->fetchall_arrayref();
   MKDEBUG && _d('Next boundary:', Dumper($boundary));
   if ( $boundary && @$boundary ) {
      $self->{upper} = $boundary->[0]; # this nibble
      if ( $boundary->[1] ) {
         $self->{next_lower} = $boundary->[1]; # next nibble
      }
      else {
         $self->{no_more_boundaries} = 1;  # for next call
         MKDEBUG && _d('Last upper boundary:', Dumper($boundary->[0]));
      }
   }
   else {
      $self->{no_more_boundaries} = 1;  # for next call
      $self->{upper} = $self->{last_upper};
      MKDEBUG && _d('Last upper boundary:', Dumper($self->{upper}));
   }
   $self->{ub_sth}->finish();

   return 1; # continue nibbling
}

sub identical_boundaries {
   my ($self, $b1, $b2) = @_;

   # If only one boundary isn't defined, then they can't be identical.
   return 0 if ($b1 && !$b2) || (!$b1 && $b2);

   # If both boundaries aren't defined, then they're identical.
   return 1 if !$b1 && !$b2;

   # Both boundaries are defined; compare their values and return false
   # on the fisrt difference because only one diff is needed to prove
   # that they're not identical.
   die "Boundaries have different numbers of values"
      if scalar @$b1 != scalar @$b2;  # shouldn't happen
   my $n_vals = scalar @$b1;
   for my $i ( 0..($n_vals-1) ) {
      return 0 if $b1->[$i] ne $b2->[$i]; # diff
   }
   return 1;
}

sub DESTROY {
   my ( $self ) = @_;
   foreach my $key ( keys %$self ) {
      if ( $key =~ m/_sth$/ ) {
         $self->{$key}->finish();
      }
   }
   return;
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
# End NibbleIterator package
# ###########################################################################
