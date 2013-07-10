# This program is copyright 2011 Percona Ireland Ltd.
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
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# Sub: new
#
# Required Arguments:
#   Cxn          - <Cxn> object
#   tbl          - Standard tbl ref
#   chunk_size   - Number of rows to nibble per chunk
#   OptionParser - <OptionParser> object
#   Quoter       - <Quoter> object
#   TableNibbler - <TableNibbler> object
#   TableParser  - <TableParser> object
#
# Optional Arguments:
#   dml         - Data manipulation statment to precede the SELECT statement
#   select      - Arrayref of table columns to select
#   chunk_index - Index to use for nibbling
#   one_nibble  - Allow one-chunk tables (default yes)
#   resume      - Hashref with lower_boundary and upper_boundary values
#                 to resume nibble from
#   order_by    - Add ORDER BY to nibble SQL (default no)
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

   # Die unless table can be nibbled, else return row estimate, nibble index,
   # and if table can be nibbled in one chunk.
   my $nibble_params = can_nibble(%args);

   # Text appended to the queries in comments so caller can identify
   # them in processlist, binlog, etc.
   my %comments = (
      bite   => "bite table",
      nibble => "nibble table",
   );
   if ( $args{comments} ) {
      map  { $comments{$_} = $args{comments}->{$_} }
      grep { defined $args{comments}->{$_}         }
      keys %{$args{comments}};
   }

   my $where      = $o->has('where') ? $o->get('where') : '';
   my $tbl_struct = $tbl->{tbl_struct};
   my $ignore_col = $o->has('ignore-columns')
                  ? ($o->get('ignore-columns') || {})
                  : {};
   my $all_cols   = $o->has('columns')
                  ? ($o->get('columns') || $tbl_struct->{cols})
                  : $tbl_struct->{cols};
   my @cols       = grep { !$ignore_col->{$_} } @$all_cols;
   my $self;
   if ( $nibble_params->{one_nibble} ) {
      # If the chunk size is >= number of rows in table, then we don't
      # need to chunk; we can just select all rows, in order, at once.
      my $nibble_sql
         = ($args{dml} ? "$args{dml} " : "SELECT ")
         . ($args{select} ? $args{select}
                          : join(', ', map { $q->quote($_) } @cols))
         . " FROM $tbl->{name}"
         . ($where ? " WHERE $where" : '')
         . ($args{lock_in_share_mode} ? " LOCK IN SHARE MODE" : "")
         . " /*$comments{bite}*/";
      PTDEBUG && _d('One nibble statement:', $nibble_sql);

      my $explain_nibble_sql
         = "EXPLAIN SELECT "
         . ($args{select} ? $args{select}
                          : join(', ', map { $q->quote($_) } @cols))
         . " FROM $tbl->{name}"
         . ($where ? " WHERE $where" : '')
         . ($args{lock_in_share_mode} ? " LOCK IN SHARE MODE" : "")
         . " /*explain $comments{bite}*/";
      PTDEBUG && _d('Explain one nibble statement:', $explain_nibble_sql);

      $self = {
         %args,
         one_nibble         => 1,
         limit              => 0,
         nibble_sql         => $nibble_sql,
         explain_nibble_sql => $explain_nibble_sql,
      };
   }
   else {
      my $index      = $nibble_params->{index}; # brevity
      my $index_cols = $tbl->{tbl_struct}->{keys}->{$index}->{cols};

      # Figure out how to nibble the table with the index.
      my $asc = $args{TableNibbler}->generate_asc_stmt(
         %args,
         tbl_struct   => $tbl->{tbl_struct},
         index        => $index,
         n_index_cols => $args{n_chunk_index_cols},
         cols         => \@cols,
         asc_only     => 1,
      );
      PTDEBUG && _d('Ascend params:', Dumper($asc));

      # Make SQL statements, prepared on first call to next().  FROM and
      # ORDER BY are the same for all statements.  FORCE IDNEX and ORDER BY
      # are needed to ensure deterministic nibbling.
      my $from     = "$tbl->{name} FORCE INDEX(`$index`)";
      my $order_by = join(', ', map {$q->quote($_)} @{$index_cols});

      # The real first row in the table.  Usually we start nibbling from
      # this row.  Called once in _get_bounds().
      my $first_lb_sql
         = "SELECT /*!40001 SQL_NO_CACHE */ "
         . join(', ', map { $q->quote($_) } @{$asc->{scols}})
         . " FROM $from"
         . ($where ? " WHERE $where" : '')
         . " ORDER BY $order_by"
         . " LIMIT 1"
         . " /*first lower boundary*/";
      PTDEBUG && _d('First lower boundary statement:', $first_lb_sql);

      # If we're resuming, this fetches the effective first row, which
      # should differ from the real first row.  Called once in _get_bounds().
      my $resume_lb_sql;
      if ( $args{resume} ) {
         $resume_lb_sql
            = "SELECT /*!40001 SQL_NO_CACHE */ "
            . join(', ', map { $q->quote($_) } @{$asc->{scols}})
            . " FROM $from"
            . " WHERE " . $asc->{boundaries}->{'>'}
            . ($where ? " AND ($where)" : '')
            . " ORDER BY $order_by"
            . " LIMIT 1"
            . " /*resume lower boundary*/";
         PTDEBUG && _d('Resume lower boundary statement:', $resume_lb_sql);
      }

      # The nibbles are inclusive, so we need to fetch the real last row
      # in the table.  Saved as boundary last_upper and used as boundary
      # upper in some cases.  Called once in _get_bounds().
      my $last_ub_sql
         = "SELECT /*!40001 SQL_NO_CACHE */ "
         . join(', ', map { $q->quote($_) } @{$asc->{scols}})
         . " FROM $from"
         . ($where ? " WHERE $where" : '')
         . " ORDER BY "
         . join(' DESC, ', map {$q->quote($_)} @{$index_cols}) . ' DESC'
         . " LIMIT 1"
         . " /*last upper boundary*/";
      PTDEBUG && _d('Last upper boundary statement:', $last_ub_sql);

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
      PTDEBUG && _d('Upper boundary statement:', $ub_sql);

      # This statement does the actual nibbling work; its rows are returned
      # to the caller via next().
      my $nibble_sql
         = ($args{dml} ? "$args{dml} " : "SELECT ")
         . ($args{select} ? $args{select}
                          : join(', ', map { $q->quote($_) } @{$asc->{cols}}))
         . " FROM $from"
         . " WHERE " . $asc->{boundaries}->{'>='}  # lower boundary
         . " AND "   . $asc->{boundaries}->{'<='}  # upper boundary
         . ($where ? " AND ($where)" : '')
         . ($args{order_by} ? " ORDER BY $order_by" : "")
         . ($args{lock_in_share_mode} ? " LOCK IN SHARE MODE" : "")
         . " /*$comments{nibble}*/";
      PTDEBUG && _d('Nibble statement:', $nibble_sql);

      my $explain_nibble_sql 
         = "EXPLAIN SELECT "
         . ($args{select} ? $args{select}
                          : join(', ', map { $q->quote($_) } @{$asc->{cols}}))
         . " FROM $from"
         . " WHERE " . $asc->{boundaries}->{'>='}  # lower boundary
         . " AND "   . $asc->{boundaries}->{'<='}  # upper boundary
         . ($where ? " AND ($where)" : '')
         . ($args{order_by} ? " ORDER BY $order_by" : "")
         . ($args{lock_in_share_mode} ? " LOCK IN SHARE MODE" : "")
         . " /*explain $comments{nibble}*/";
      PTDEBUG && _d('Explain nibble statement:', $explain_nibble_sql);

      my $limit = $chunk_size - 1;
      PTDEBUG && _d('Initial chunk size (LIMIT):', $limit);

      $self = {
         %args,
         index                => $index,
         limit                => $limit,
         first_lb_sql         => $first_lb_sql,
         last_ub_sql          => $last_ub_sql,
         ub_sql               => $ub_sql,
         nibble_sql           => $nibble_sql,
         explain_first_lb_sql => "EXPLAIN $first_lb_sql",
         explain_ub_sql       => "EXPLAIN $ub_sql",
         explain_nibble_sql   => $explain_nibble_sql,
         resume_lb_sql        => $resume_lb_sql,
         sql                  => {
            columns    => $asc->{scols},
            from       => $from,
            where      => $where,
            boundaries => $asc->{boundaries},
            order_by   => $order_by,
         },
      };
   }

   $self->{row_est}    = $nibble_params->{row_est},
   $self->{nibbleno}   = 0;
   $self->{have_rows}  = 0;
   $self->{rowno}      = 0;
   $self->{oktonibble} = 1;

   return bless $self, $class;
}

sub next {
   my ($self) = @_;

   if ( !$self->{oktonibble} ) {
      PTDEBUG && _d('Not ok to nibble');
      return;
   }

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
         $self->{oktonibble} = $callback->(%callback_args);
         PTDEBUG && _d('init callback returned', $self->{oktonibble});
         if ( !$self->{oktonibble} ) {
            $self->{no_more_boundaries} = 1;
            return;
         }
      }
      if ( !$self->{one_nibble} && !$self->{first_lower} ) {
         PTDEBUG && _d('No first lower boundary, table must be empty');
         $self->{no_more_boundaries} = 1;
         return;
      }
   }

   # If there's another nibble, fetch the rows within it.
   NIBBLE:
   while ( $self->{have_rows} || $self->_next_boundaries() ) {
      # If no rows, then we just got the next boundaries, which start
      # the next nibble.
      if ( !$self->{have_rows} ) {
         $self->{nibbleno}++;
         PTDEBUG && _d('Nibble:', $self->{nibble_sth}->{Statement}, 'params:',
            join(', ', (@{$self->{lower} || []}, @{$self->{upper} || []})));
         if ( my $callback = $self->{callbacks}->{exec_nibble} ) {
            $self->{have_rows} = $callback->(%callback_args);
         }
         else {
            # XXX This call and others like it are relying on a Perl oddity.
            # See https://bugs.launchpad.net/percona-toolkit/+bug/987393
            $self->{nibble_sth}->execute(@{$self->{lower}}, @{$self->{upper}});
            $self->{have_rows} = $self->{nibble_sth}->rows();
         }
         PTDEBUG && _d($self->{have_rows}, 'rows in nibble', $self->{nibbleno});
      }

      # Return rows in this nibble.
      if ( $self->{have_rows} ) {
         # Return rows in nibble.  sth->{Active} is always true with
         # DBD::mysql v3, so we track the status manually.
         my $row = $self->{nibble_sth}->fetchrow_arrayref();
         if ( $row ) {
            $self->{rowno}++;
            PTDEBUG && _d('Row', $self->{rowno}, 'in nibble',$self->{nibbleno});
            # fetchrow_arraryref re-uses an internal arrayref, so we must copy.
            return [ @$row ];
         }
      }

      PTDEBUG && _d('No rows in nibble or nibble skipped');
      if ( my $callback = $self->{callbacks}->{after_nibble} ) {
         $callback->(%callback_args);
      }
      $self->{rowno}     = 0;
      $self->{have_rows} = 0;
   }

   PTDEBUG && _d('Done nibbling');
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
   PTDEBUG && _d('Set new nibble number:', $n);
   return;
}

sub nibble_index {
   my ($self) = @_;
   return $self->{index};
}

sub statements {
   my ($self) = @_;
   return {
      explain_first_lower_boundary => $self->{explain_first_lb_sth},
      nibble                       => $self->{nibble_sth},
      explain_nibble               => $self->{explain_nibble_sth},
      upper_boundary               => $self->{ub_sth},
      explain_upper_boundary       => $self->{explain_ub_sth},
   }
}

sub boundaries {
   my ($self) = @_;
   return {
      first_lower => $self->{first_lower},
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
   PTDEBUG && _d('Set new', $boundary, 'boundary:', Dumper($values));
   return;
}

sub one_nibble {
   my ($self) = @_;
   return $self->{one_nibble};
}

sub chunk_size {
   my ($self) = @_;
   return $self->{limit} + 1;
}

sub set_chunk_size {
   my ($self, $limit) = @_;
   return if $self->{one_nibble};
   die "Chunk size must be > 0" unless $limit;
   $self->{limit} = $limit - 1;
   PTDEBUG && _d('Set new chunk size (LIMIT):', $limit);
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

sub can_nibble {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl chunk_size OptionParser TableParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($cxn, $tbl, $chunk_size, $o) = @args{@required_args};

   my $where = $o->has('where') ? $o->get('where') : '';

   # About how many rows are there?
   my ($row_est, $mysql_index) = get_row_estimate(
      Cxn   => $cxn,
      tbl   => $tbl,
      where => $where,
   );

   # MySQL's chosen index is only something we should prefer
   # if --where is used.  Else, we can chose our own index
   # and disregard the MySQL index from the row estimate.
   # If there's a --where, however, then MySQL's chosen index
   # is used because it tells us how MySQL plans to optimize
   # for the --where.
   # https://bugs.launchpad.net/percona-toolkit/+bug/978432
   if ( !$where ) {
      $mysql_index = undef;
   }

   # Can all those rows be nibbled in one chunk?  If one_nibble is defined,
   # then do as it says; else, look at the chunk size limit.  If the chunk
   # size limit is disabled (=0), then use the chunk size because there
   # always needs to be a limit to the one-chunk table.
   my $chunk_size_limit = $o->get('chunk-size-limit') || 1;
   my $one_nibble = !defined $args{one_nibble} || $args{one_nibble}
                  ? $row_est <= $chunk_size * $chunk_size_limit
                  : 0;
   PTDEBUG && _d('One nibble:', $one_nibble ? 'yes' : 'no');

   # Special case: we're resuming and there's no boundaries, so the table
   # being resumed was originally nibbled in one chunk, so do the same again.
   if ( $args{resume}
        && !defined $args{resume}->{lower_boundary}
        && !defined $args{resume}->{upper_boundary} ) {
      PTDEBUG && _d('Resuming from one nibble table');
      $one_nibble = 1;
   }

   # Get an index to nibble by.  We'll order rows by the index's columns.
   my $index = _find_best_index(%args, mysql_index => $mysql_index);
   if ( !$index && !$one_nibble ) {
      die "There is no good index and the table is oversized.";
   }

   # The table can be nibbled if this point is reached, else we would have
   # died earlier.  Return some values about nibbling the table.
   return {
      row_est     => $row_est,      # nibble about this many rows
      index       => $index,        # using this index
      one_nibble  => $one_nibble,   # if the table fits in one nibble/chunk
   };
}

sub _find_best_index {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl TableParser);
   my ($cxn, $tbl, $tp) = @args{@required_args};
   my $tbl_struct = $tbl->{tbl_struct};
   my $indexes    = $tbl_struct->{keys};

   my $want_index = $args{chunk_index};
   if ( $want_index ) {
      PTDEBUG && _d('User wants to use index', $want_index);
      if ( !exists $indexes->{$want_index} ) {
         PTDEBUG && _d('Cannot use user index because it does not exist');
         $want_index = undef;
      }
   }

   if ( !$want_index && $args{mysql_index} ) {
      PTDEBUG && _d('MySQL wants to use index', $args{mysql_index});
      $want_index = $args{mysql_index};
   }

   my $best_index;
   my @possible_indexes;
   if ( $want_index ) {
      if ( $indexes->{$want_index}->{is_unique} ) {
         PTDEBUG && _d('Will use wanted index');
         $best_index = $want_index;
      }
      else {
         PTDEBUG && _d('Wanted index is a possible index');
         push @possible_indexes, $want_index;
      }
   }
   else {
      PTDEBUG && _d('Auto-selecting best index');
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
      PTDEBUG && _d('No PRIMARY or unique indexes;',
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
            = $indexes->{$b}->{cardinality} <=> $indexes->{$a}->{cardinality};
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

   PTDEBUG && _d('Best index:', $best_index);
   return $best_index;
}

sub _get_index_cardinality {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl index);
   my ($cxn, $tbl, $index) = @args{@required_args};

   my $sql = "SHOW INDEXES FROM $tbl->{name} "
           . "WHERE Key_name = '$index'";
   PTDEBUG && _d($sql);
   my $cardinality = 1;
   my $dbh         = $cxn->dbh();
   my $key_name    = $dbh && ($dbh->{FetchHashKeyName} || '') eq 'NAME_lc'
                   ? 'key_name'
                   : 'Key_name';
   my $rows = $dbh->selectall_hashref($sql, $key_name);
   foreach my $row ( values %$rows ) {
      $cardinality *= $row->{cardinality} if $row->{cardinality};
   }
   PTDEBUG && _d('Index', $index, 'cardinality:', $cardinality);
   return $cardinality;
}

sub get_row_estimate {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($cxn, $tbl) = @args{@required_args};

   my $sql = "EXPLAIN SELECT * FROM $tbl->{name} "
           . "WHERE " . ($args{where} || '1=1');
   PTDEBUG && _d($sql);
   my $expl = $cxn->dbh()->selectrow_hashref($sql);
   PTDEBUG && _d(Dumper($expl));
   # MySQL's chosen index must be lowercase because TableParser::parse()
   # lowercases all idents (search in that module for \L) except for
   # the PRIMARY KEY which it leaves uppercase.
   # https://bugs.launchpad.net/percona-toolkit/+bug/995274
   my $mysql_index = $expl->{key} || '';
   if ( $mysql_index ne 'PRIMARY' ) {
      $mysql_index = lc($mysql_index);
   }
   return ($expl->{rows} || 0), $mysql_index;
}

sub _prepare_sths {
   my ($self) = @_;
   PTDEBUG && _d('Preparing statement handles');

   my $dbh = $self->{Cxn}->dbh();

   $self->{nibble_sth}         = $dbh->prepare($self->{nibble_sql});
   $self->{explain_nibble_sth} = $dbh->prepare($self->{explain_nibble_sql});

   if ( !$self->{one_nibble} ) {
      $self->{explain_first_lb_sth} = $dbh->prepare($self->{explain_first_lb_sql});
      $self->{ub_sth}               = $dbh->prepare($self->{ub_sql});
      $self->{explain_ub_sth}       = $dbh->prepare($self->{explain_ub_sql});
   }

   return;
}

sub _get_bounds { 
   my ($self) = @_;

   if ( $self->{one_nibble} ) {
      if ( $self->{resume} ) {
         $self->{no_more_boundaries} = 1;
      }
      return;
   }

   my $dbh = $self->{Cxn}->dbh();

   # Get the real first lower boundary.
   $self->{first_lower} = $dbh->selectrow_arrayref($self->{first_lb_sql});
   PTDEBUG && _d('First lower boundary:', Dumper($self->{first_lower}));  

   # The next boundary is the first lower boundary.  If resuming,
   # this should be something > the real first lower boundary and
   # bounded (else it's not one of our chunks).
   if ( my $nibble = $self->{resume} ) {
      if (    defined $nibble->{lower_boundary}
           && defined $nibble->{upper_boundary} ) {
         my $sth = $dbh->prepare($self->{resume_lb_sql});
         my @ub  = split ',', $nibble->{upper_boundary};
         PTDEBUG && _d($sth->{Statement}, 'params:', @ub);
         $sth->execute(@ub);
         $self->{next_lower} = $sth->fetchrow_arrayref();
         $sth->finish();
      }
   }
   else {
      $self->{next_lower}  = $self->{first_lower};   
   }
   PTDEBUG && _d('Next lower boundary:', Dumper($self->{next_lower}));  

   if ( !$self->{next_lower} ) {
      # This happens if we resume from the end of the table, or if the
      # last chunk for resuming isn't bounded.
      PTDEBUG && _d('At end of table, or no more boundaries to resume');
      $self->{no_more_boundaries} = 1;

      # Get the real last upper boundary, i.e. the last row of the table
      # at this moment.  If rows are inserted after, we won't see them.
      # This is required for OobNibbleIterator because if we resume at
      # the lower or upper oob nibble, we also need to know the last upper
      # boundary of the table (we already have the first).
      $self->{last_upper} = $dbh->selectrow_arrayref($self->{last_ub_sql});
      PTDEBUG && _d('Last upper boundary:', Dumper($self->{last_upper}));
   }

   return;
}

sub _next_boundaries {
   my ($self) = @_;

   if ( $self->{no_more_boundaries} ) {
      PTDEBUG && _d('No more boundaries');
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
      PTDEBUG && _d('Infinite loop detected');
      my $tbl     = $self->{tbl};
      my $index   = $tbl->{tbl_struct}->{keys}->{$self->{index}};
      my $n_cols  = scalar @{$index->{cols}};
      my $chunkno = $self->{nibbleno};

      # XXX This call and others like it are relying on a Perl oddity.
      # See https://bugs.launchpad.net/percona-toolkit/+bug/987393
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
      PTDEBUG && _d('next_boundaries callback returned', $oktonibble);
      if ( !$oktonibble ) {
         $self->{no_more_boundaries} = 1;
         return; # stop nibbling
      }
   }

   # Two boundaries are being fetched: the upper boundary for this nibble,
   # i.e. the nibble the caller is trying to exec, and the next_lower boundary
   # for the next nibble that the caller will try to exec.  For example,
   # if chunking the alphabet, a-z, with chunk size 3, the first call will
   # fetch:
   #
   #    a <- lower
   #    b
   #    c <- upper      ($boundary->[0])
   #    d <- next_lower ($boundary->[1])
   #
   # Then the second call will fetch:
   #
   #    d <- lower
   #    e
   #    f <- upper
   #    g <- next_lower
   #
   # Why fetch both upper and next_lower?  We wanted to keep nibbling simple,
   # i.e. one nibble statment, not one for the first nibble, one for "middle"
   # nibbles, and another for the end (this is how older code worked).  So the
   # nibble statement is inclusive, but this requires both boundaries for
   # reasons explained in a comment above my $ub_sql in new().

   # XXX This call and others like it are relying on a Perl oddity.
   # See https://bugs.launchpad.net/percona-toolkit/+bug/987393
   PTDEBUG && _d($self->{ub_sth}->{Statement}, 'params:',
      join(', ', @{$self->{lower}}), $self->{limit});
   $self->{ub_sth}->execute(@{$self->{lower}}, $self->{limit});
   my $boundary = $self->{ub_sth}->fetchall_arrayref();
   PTDEBUG && _d('Next boundary:', Dumper($boundary));
   if ( $boundary && @$boundary ) {
      # upper boundary for the current nibble.
      $self->{upper} = $boundary->[0];

      if ( $boundary->[1] ) {
         # next_lower boundary for the next nibble (will become the lower
         # boundary when that nibble becomes the current nibble).
         $self->{next_lower} = $boundary->[1];
      }
      else {
         # There's no next_lower boundary, so the upper boundary of
         # the current nibble is the end of the table.  For example,
         # if chunking a-z, then the upper boundary of the current
         # nibble ($boundary->[0]) is z.
         PTDEBUG && _d('End of table boundary:', Dumper($boundary->[0]));
         $self->{no_more_boundaries} = 1;  # for next call

         # OobNibbleIterator needs to know the last upper boundary.
         $self->{last_upper} = $boundary->[0];
      }
   }
   else {
      # This code is reached in cases like chunking a-z and the next_lower
      # boundary ($boundary->[1]) falls on z.  When called again, no upper
      # or next_lower is found past z so if($boundary && @$boundary) is false.
      # But there's a problem: between the previous call that made next_lower=z
      # and this call, rows might have been inserted, so maybe z is no longer
      # the end of the table.  To handle this, we fetch the end of the table
      # once and make the final nibble z-<whatever>.
      my $dbh = $self->{Cxn}->dbh();
      $self->{upper} = $dbh->selectrow_arrayref($self->{last_ub_sql});
      PTDEBUG && _d('Last upper boundary:', Dumper($self->{upper}));
      $self->{no_more_boundaries} = 1;  # for next call
      
      # OobNibbleIterator needs to know the last upper boundary.
      $self->{last_upper} = $self->{upper};
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
         PTDEBUG && _d('Finish', $key);
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
