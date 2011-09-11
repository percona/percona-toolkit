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

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(dbh tbl OptionParser Quoter TableNibbler TableParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $tbl, $o, $q) = @args{@required_args};

   # Get an index to nibble by.  We'll order rows by the index's columns.
   my $index = $args{TableParser}->find_best_index(
      $tbl->{tbl_struct},
      $o->get('chunk-index'),
   );
   die "No index to nibble table $tbl->{db}.$tbl->{tbl}" unless $index;
   my $index_cols = $tbl->{tbl_struct}->{keys}->{$index}->{cols};

   # Figure out how to nibble the table with the index.
   my $asc = $args{TableNibbler}->generate_asc_stmt(
      %args,
      tbl_struct => $tbl->{tbl_struct},
      index      => $index,
      asc_only   => 1,
   );

   # Make SQL statements, prepared on first call to next().  FROM and
   # ORDER BY are the same for all statements.  FORCE IDNEX and ORDER BY
   # are needed to ensure deterministic nibbling.
   my $from     = $q->quote(@{$tbl}{qw(db tbl)}) . " FORCE INDEX(`$index`)";
   my $order_by = join(', ', map {$q->quote($_)} @{$index_cols});

   # These statements are only executed once, so they don't use sths.
   my $first_lb_sql
      = "SELECT /*!40001 SQL_NO_CACHE */ "
      . join(', ', map { $q->quote($_) } @{$index_cols})
      . " FROM $from "
      . ($args{where} ? " WHERE $args{where}" : '')
      . " ORDER BY $order_by "
      . " LIMIT 1"
      . " /*first lower boundary*/";
   MKDEBUG && _d('First lower boundary statement:', $first_lb_sql);

   my $last_ub_sql
      = "SELECT /*!40001 SQL_NO_CACHE */ "
      . join(', ', map { $q->quote($_) } @{$index_cols})
      . " FROM $from "
      . ($args{where} ? " WHERE $args{where}" : '')
      . " ORDER BY $order_by DESC "
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
      . join(', ', map { $q->quote($_) } @{$index_cols})
      . " FROM $from "
      . " WHERE " . $asc->{boundaries}->{'>='}  # lower boundary
      . ($args{where} ? " AND ($args{where})" : '')
      . " ORDER BY $order_by "
      . " LIMIT 2 OFFSET " . (($o->get('chunk-size') || 1) - 1)
      . " /*upper boundary*/";
   MKDEBUG && _d('Next upper boundary statement:', $ub_sql);

   my $nibble_sql
      = ($args{dms} ? "$args{dms} " : "SELECT ")
      . ($args{select} ? $args{select}
                       : join(', ', map { $q->quote($_) } @{$asc->{cols}}))
      . " FROM $from "
      . " WHERE " . $asc->{boundaries}->{'>='}  # lower boundary
      . " AND "   . $asc->{boundaries}->{'<='}  # upper boundary
      . ($args{where} ? " AND ($args{where})" : '')
      . " ORDER BY $order_by"
      . " /*nibble*/";
   MKDEBUG && _d('Nibble statement:', $nibble_sql);

   # If the chunk size is >= number of rows in table, then we don't
   # need to chunk; we can just select all rows, in order, at once.
   my $one_nibble_sql
      = ($args{dms} ? "$args{dms} " : "SELECT ")
      . ($args{select} ? $args{select}
                       : join(', ', map { $q->quote($_) } @{$asc->{cols}}))
      . " FROM $from "
      . ($args{where} ? " AND ($args{where})" : '')
      . " ORDER BY $order_by"
      . " /*one nibble*/";
   MKDEBUG && _d('One nibble statement:', $one_nibble_sql);

   my $self = {
      %args,
      index          => $index,
      first_lb_sql   => $first_lb_sql,
      last_ub_sql    => $last_ub_sql,
      ub_sql         => $ub_sql,
      nibble_sql     => $nibble_sql,
      one_nibble_sql => $one_nibble_sql,
      nibbleno       => 0,
      have_rows      => 0,
      rowno          => 0,
   };

   return bless $self, $class;
}

sub next {
   my ($self) = @_;

   # First call, init everything.  This could be done in new(), but
   # all work is delayed until actually needed.
   if ($self->{nibbleno} == 0) {
      $self->_can_nibble_once();
      $self->_prepare_sths();
      $self->_get_bounds();
      # $self->_check_index_usage();
      if ( my $callback = $self->{callbacks}->{init} ) {
         $callback->();
      }
   }

   # Return rows in nibble.  sth->{Active} is always true with DBD::mysql v3,
   # so we track the status manually.  have_rows will be true if a previous
   # call got a nibble with rows.  When there's no more rows in this nibble,
   # try to get the next nibble.
   if ( $self->{have_rows} ) {
      my $row = $self->{nibble_sth}->fetchrow_arrayref();
      if ( $row ) {
         $self->{rowno}++;
         MKDEBUG && _d('Row', $self->{rowno}, 'in nibble', $self->{nibbleno});
         # fetchrow_arraryref re-uses its internal arrayref, so we must copy.
         return [ @$row ];
      }
      MKDEBUG && _d('No more rows in nibble', $self->{nibbleno});
      if ( my $callback = $self->{callbacks}->{after_nibble} ) {
         $callback->(
            dbh => $self->{dbh},
            tbl => $self->{tbl},
         );
      }
      $self->{rowno}     = 0;
      $self->{have_rows} = 0;
   }

   # If there's another boundary, fetch the rows within it.
   BOUNDARY:
   while ( $self->_next_boundaries() ) {
      $self->{nibbleno}++;
      MKDEBUG && _d($self->{nibble_sth}->{Statement}, 'params:',
         join(', ', (@{$self->{lb}}, @{$self->{ub}})));
      if ( my $callback = $self->{callbacks}->{exec_nibble} ) {
         $self->{have_rows} = $callback->(
            dbh => $self->{dbh},
            tbl => $self->{tbl},
            sth => $self->{nibble_sth},
            lb  => $self->{lb},
            ub  => $self->{ub},
         );
      }
      else {
         $self->{nibble_sth}->execute(@{$self->{lb}}, @{$self->{ub}});
         $self->{have_rows} = $self->{nibble_sth}->rows();
      }
      if ( $self->{have_rows} ) {
         MKDEBUG && _d($self->{have_rows}, 'rows in nibble', $self->{nibbleno});
         return $self->next();
      }
      MKDEBUG && _d('No rows in nibble or nibble skipped');
      next BOUNDARY;
   }

   MKDEBUG && _d('Done nibbling');
   if ( my $callback = $self->{callbacks}->{done} ) {
      $callback->(
         dbh => $self->{dbh},
         tbl => $self->{tbl},
      );
   }
   return;
}

sub nibble_number {
   my ($self) = @_;
   return $self->{nibbleno};
}

sub _can_nibble_once {
   my ($self) = @_;
   my ($dbh, $tbl, $q) = @{$self}{qw(dbh tbl Quoter)};
   my $table_status;
   eval {
      my $sql = "SHOW TABLE STATUS FROM " . $q->quote($tbl->{db})
              . " LIKE " . $q->literal_like($tbl->{tbl});
      MKDEBUG && _d($sql);
      $table_status = $dbh->selectrow_hashref($sql);
      MKDEBUG && _d('Table status:', Dumper($table_status));
   };
   if ( $EVAL_ERROR ) {
      warn $EVAL_ERROR;
      return 0;
   }
   my $n_rows = defined $table_status->{Rows} ? $table_status->{Rows}
              : defined $table_status->{rows} ? $table_status->{rows}
              : 0;
   my $chunk_size = $self->{OptionParser}->get('chunk-size') || 1;
   $self->{one_nibble} = $n_rows <= $chunk_size ? 1 : 0;
   MKDEBUG && _d('One nibble:', $self->{one_nibble} ? 'yes' : 'no');
   return $self->{one_nibble};
}

sub _prepare_sths {
   my ($self) = @_;
   MKDEBUG && _d('Preparing statement handles');
   if ( $self->{one_nibble} ) {
      $self->{nibble_sth} = $self->{dbh}->prepare($self->{one_nibble_sql});
   }
   else {
      $self->{ub_sth} = $self->{dbh}->prepare($self->{ub_sql});
      $self->{nibble_sth} = $self->{dbh}->prepare($self->{nibble_sql});
   }
}

sub _get_bounds { 
   my ($self) = @_;
   return if $self->{one_nibble};

   $self->{next_lb} = $self->{dbh}->selectrow_arrayref($self->{first_lb_sql});
   MKDEBUG && _d('First lower boundary:', Dumper($self->{next_lb}));
   
   $self->{last_ub} = $self->{dbh}->selectrow_arrayref($self->{last_ub_sql});
   MKDEBUG && _d('Last upper boundary:', Dumper($self->{last_ub}));
   
   return;
}

sub _check_index_usage {
   my ($self) = @_;
   my ($dbh, $tbl, $q) = @{$self}{qw(dbh tbl Quoter)};

   my $explain;
   eval {
      $explain = $dbh->selectall_arrayref("", {Slice => {}});
   };
   if ( $EVAL_ERROR ) {
      warn "Cannot check if MySQL is using the chunk index: $EVAL_ERROR";
      return;
   }
   my $explain_index = lc($explain->[0]->{key} || '');
   MKDEBUG && _d('EXPLAIN index:', $explain_index);
   if ( $explain_index ne $self->{index} ) {
      die "Cannot nibble table $tbl->{db}.$tbl->{tbl} because MySQL chose "
         . ($explain_index ? "the `$explain_index`" : 'no') . ' index'
         . " instead of the chunk index `$self->{asc}->{index}`";
   }

   return;
}

sub _next_boundaries {
   my ($self) = @_;

   if ( $self->{no_more_boundaries} ) {
      MKDEBUG && _d('No more boundaries');
      return;
   }

   if ( $self->{one_nibble} ) {
      $self->{lb} = $self->{ub} = [];
      $self->{no_more_boundaries} = 1;  # for next call
      return 1;
   }

   $self->{lb} = $self->{next_lb};

   MKDEBUG && _d($self->{ub_sth}->{Statement}, 'params:',
      join(', ', @{$self->{lb}}));
   $self->{ub_sth}->execute(@{$self->{lb}});
   my $boundary = $self->{ub_sth}->fetchall_arrayref();
   MKDEBUG && _d('Next boundary:', Dumper($boundary));
   if ( $boundary && @$boundary ) {
      $self->{ub} = $boundary->[0]; # this nibble
      if ( $boundary->[1] ) {
         $self->{next_lb} = $boundary->[1]; # next nibble
      }
      else {
         $self->{no_more_boundaries} = 1;  # for next call
         MKDEBUG && _d('Last upper boundary:', Dumper($boundary->[0]));
      }
   }
   else {
      $self->{no_more_boundaries} = 1;  # for next call
      $self->{ub} = $self->{last_ub};
      MKDEBUG && _d('Last upper boundary:', Dumper($self->{ub}));
   }
   $self->{ub_sth}->finish();

   return 1; # have boundary
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
