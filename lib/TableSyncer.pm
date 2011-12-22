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
# TableSyncer package
# ###########################################################################
{
# Package: TableSyncer
# TableSyncer helps sync tables with various table sync algo modules.
package TableSyncer;

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
   my @required_args = qw(MasterSlave OptionParser Quoter TableParser
                          TableNibbler RowChecksum RowDiff Retry);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

# Required arguments:
#   * plugins         Arrayref of TableSync* modules, in order of preference
#   * src             Hashref with source (aka left) dbh, db, tbl
#   * dst             Hashref with destination (aka right) dbh, db, tbl
#   * tbl_struct      Return val from TableParser::parser() for src and dst tbl
#   * cols            Arrayref of column names to checksum/compare
#   * chunk_size      Size/number of rows to select in each chunk
#   * RowDiff         A RowDiff module
#   * ChangeHandler   A ChangeHandler module
# Optional arguments:
#   * where           WHERE clause to restrict synced rows (default none)
#   * bidirectional   If doing bidirectional sync (default no)
#   * changing_src    If making changes on src (default no)
#   * replicate       Checksum table if syncing via replication (default no)
#   * function        Crypto hash func for checksumming chunks (default CRC32)
#   * dry_run         Prepare to sync but don't actually sync (default no)
#   * chunk_col       Column name to chunk table on (default auto-choose)
#   * chunk_index     Index name to use for chunking table (default auto-choose)
#   * index_hint      Use FORCE/USE INDEX (chunk_index) (default yes)
#   * buffer_in_mysql  Use SQL_BUFFER_RESULT (default no)
#   * buffer_to_client Use mysql_use_result (default no)
#   * callback        Sub called before executing the sql (default none)
#   * trace           Append trace message to change statements (default yes)
#   * transaction     locking
#   * change_dbh      locking
#   * lock            locking
#   * wait            locking
sub sync_table {
   my ( $self, %args ) = @_;
   my @required_args = qw(src dst RowSyncer ChangeHandler);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($src, $dst, $row_syncer, $changer) = @args{@required_args};

   my $diffs        = $args{diffs};
   my $changing_src = $args{changing_src};

   my $o            = $self->{OptionParser};
   my $q            = $self->{Quoter};
   my $row_diff     = $self->{RowDiff};
   my $row_checksum = $self->{RowChecksum};

   # USE db on src and dst for cases like when replicate-do-db is being used.
   foreach my $host ( $src, $dst ) {
      $host->{Cxn}->dbh()->do("USE " . $q->quote($host->{tbl}->{db}));
   }

   my $trace;
   if ( !defined $args{trace} || $args{trace} ) {
      chomp(my $hostname = `hostname`);
      $trace = "src_host:" . $src->{Cxn}->name()
             . " src_tbl:" . join('.', @{$src->{tbl}}{qw(db tbl)})
             . " dst_host:" . $dst->{Cxn}->name()
             . " dst_tbl:" . join('.', @{$dst->{tbl}}{qw(db tbl)})
             . " changing_src:" . ($changing_src ? "yes" : "no")
             . " diffs:" . ($diffs ? scalar @$diffs : "0")
             . " " . join(" ", map { "$_:" . ($o->get($_) ? "yes" : "no") }
                        qw(lock transaction replicate bidirectional))
             . " pid:$PID "
             . ($ENV{USER} ? "user:$ENV{USER} " : "")
             . ($hostname  ? "host:$hostname"   : "");
      MKDEBUG && _d("Binlog trace message:", $trace);
   }

   # Make NibbleIterator for checksumming chunks of rows to see if
   # there are any diffs.
   my %crc_args = $row_checksum->get_crc_args(dbh => $src->{Cxn}->dbh());
   my $chunk_cols;
   if ( $diffs ) {
      $chunk_cols = "0 AS cnt, '' AS crc";
   }
   else {
      
      $chunk_cols = $row_checksum->make_chunk_checksum(
         dbh => $src->{Cxn}->dbh(),
         tbl => $src->{tbl},
         %crc_args
      );
   }

   if ( !defined $src->{select_lock} || !defined $dst->{select_lock} ) {
      if ( $o->get('transaction') ) {
         if ( $o->get('bidirectional') ) {
            # Making changes on src and dst.
            $src->{select_lock} = 'FOR UPDATE';
            $dst->{select_lock} = 'FOR UPDATE';
         }
         elsif ( $changing_src ) {
            # Making changes on master (src) which replicate to slave (dst).
            $src->{select_lock} = 'FOR UPDATE';
            $dst->{select_lock} = 'LOCK IN SHARE MODE';
         }
         else {
            # Making changes on slave (dst).
            $src->{select_lock} = 'LOCK IN SHARE MODE';
            $dst->{select_lock} = 'FOR UPDATE';
         }
      }
      else {
         $src->{select_lock} = '';
         $dst->{select_lock} = '';
      }
      MKDEBUG && _d('SELECT lock:', $src->{select_lock});
      MKDEBUG && _d('SELECT lock:', $dst->{select_lock});
   }

   my $user_where = $o->get('where');

   my ($src_nibble_iter, $dst_nibble_iter);
   foreach my $host ($src, $dst) {
      my $callbacks = {
         init => sub {
            my (%args) = @_;
            my $cxn         = $args{Cxn};
            my $tbl         = $args{tbl};
            my $nibble_iter = $args{NibbleIterator};
            my $sths        = $nibble_iter->statements();
            my $oktonibble  = 1;

            if ( $o->get('explain') ) {
               # --explain level 1: print the checksum and next boundary
               # statements.
               print "--\n"
                   . "-- "
                     . ($cxn->{is_source} ? "Source" : "Destination")
                     . " " . $cxn->name()
                     . " " . "$tbl->{db}.$tbl->{tbl}\n"
                   . "--\n\n";
               my $statements = $nibble_iter->statements();
               foreach my $sth ( sort keys %$statements ) {
                  next if $sth =~ m/^explain/;
                  if ( $statements->{$sth} ) {
                     print $statements->{$sth}->{Statement}, "\n\n";
                  }
               }

               if ( $o->get('explain') < 2 ) {
                  $oktonibble = 0; # don't nibble table; next table
               }
            }
            else {
               if ( $o->get('buffer-to-client') ) {
                  $host->{sth}->{mysql_use_result} = 1;
               }

               # Lock the table.
               $self->lock_and_wait(
                  lock_level   => 2,
                  host         => $host,
                  src          => $src,
                  changing_src => $changing_src,
               );
            }
 
            return $oktonibble;
         },
         next_boundaries => sub {
            my (%args) = @_;
            my  $tbl = $args{tbl};
            if ( my $diff = $tbl->{diff} ) { 
               my $nibble_iter = $args{NibbleIterator};
               my $boundary    = $nibble_iter->boundaries();
               $nibble_iter->set_boundary(
                  'upper', [ split ',', $diff->{upper_boundary} ]);
               $nibble_iter->set_boundary(
                  'lower', [ split ',', $diff->{lower_boundary} ]);
            }
            return 1;
         },
         exec_nibble => sub {
            my (%args) = @_;
            my $tbl         = $args{tbl};
            my $nibble_iter = $args{NibbleIterator};
            my $sths        = $nibble_iter->statements();
            my $boundary    = $nibble_iter->boundaries();

            # --explain level 2: print chunk,lower boundary values,upper
            # boundary values.
            if ( $o->get('explain') > 1 ) {
               my $lb_quoted = join(',', @{$boundary->{lower} || []});
               my $ub_quoted = join(',', @{$boundary->{upper} || []});
               my $chunk     = $nibble_iter->nibble_number();
               printf "%d %s %s\n",
                  $chunk,
                  (defined $lb_quoted ? $lb_quoted : '1=1'),
                  (defined $ub_quoted ? $ub_quoted : '1=1');
               if ( !$nibble_iter->more_boundaries() ) {
                  print "\n"; # blank line between this table and the next table
               }
               return 0;  # next boundary
            }

            # Lock the chunk.
            $self->lock_and_wait(
               %args,
               lock_level   => 1,
               host         => $host,
               src          => $src,
               changing_src => $changing_src,
            );

            # Execute the chunk checksum statement.
            # The nibble iter will return the row.
            MKDEBUG && _d('nibble', $args{Cxn}->name());
            $sths->{nibble}->execute(@{$boundary->{lower}}, @{$boundary->{upper}});
            return 1;
         },
      };

      my $nibble_iter = new NibbleIterator(
         Cxn           => $host->{Cxn},
         tbl           => $host->{tbl},
         chunk_size    => $o->get('chunk-size'),
         chunk_index   => $diffs ? $diffs->[0]->{chunk_index}
                          :        $o->get('chunk-index'),
         manual_nibble => $diffs ? 1 : 0,
         empty_results => 1,
         select        => $chunk_cols,
         select_lock   => $host->{select_lock},
         callbacks     => $callbacks,
         fetch_hashref => 1,
         one_nibble    => $args{one_nibble},
         OptionParser  => $self->{OptionParser},
         Quoter        => $self->{Quoter},
         TableNibbler  => $self->{TableNibbler},
         TableParser   => $self->{TableParser},
         RowChecksum   => $self->{RowChecksum},
      );

      if ( $host->{Cxn}->{is_source} ) {
         $src_nibble_iter = $nibble_iter;
      }
      else {
         $dst_nibble_iter = $nibble_iter;
      }
   }

   my $index    = $src_nibble_iter->nibble_index();
   my $key_cols = $index ? $src->{tbl}->{tbl_struct}->{keys}->{$index}->{cols}
                         : $src->{tbl}->{tbl_struct}->{cols};
   $row_syncer->set_key_cols($key_cols);

   my $crc_col = 'crc';
   while ( $src->{tbl}->{tbl_struct}->{is_col}->{$crc_col} ) {
      $crc_col = "_$crc_col"; # Prepend more _ until not a column.
   }
   $row_syncer->set_crc_col($crc_col);
   MKDEBUG && _d('CRC column:', $crc_col);

   my $rows_sql;
   my $row_cols = $row_checksum->make_row_checksum(
      dbh => $src->{Cxn}->dbh(),
      tbl => $src->{tbl},
      %crc_args,
   );
   my $sql_clause = $src_nibble_iter->sql();
   foreach my $host ($src, $dst) {
      if ( $src_nibble_iter->one_nibble() ) {
         $rows_sql
            =  'SELECT /*rows in nibble*/ '
            . ($self->{buffer_in_mysql} ? 'SQL_BUFFER_RESULT ' : '')
            . "$row_cols AS $crc_col"
            . " FROM " . $q->quote(@{$host->{tbl}}{qw(db tbl)})
            . " WHERE 1=1 "
            . ($user_where ? " AND ($user_where)" : '')
            . ($sql_clause->{order_by} ? " ORDER BY " . $sql_clause->{order_by}
                                       : "");
      }
      else {
         $rows_sql
            =  'SELECT /*rows in nibble*/ '
            . ($self->{buffer_in_mysql} ? 'SQL_BUFFER_RESULT ' : '')
            . "$row_cols AS $crc_col"
            . " FROM " . $q->quote(@{$host->{tbl}}{qw(db tbl)})
            . " WHERE " . $sql_clause->{boundaries}->{'>='}  # lower boundary
            . " AND "   . $sql_clause->{boundaries}->{'<='}  # upper boundary
            . ($user_where ? " AND ($user_where)" : '')
            . " ORDER BY " . $sql_clause->{order_by};
      }
      $host->{rows_sth} = $host->{Cxn}->dbh()->prepare($rows_sql);
   }

   # ########################################################################
   # Start syncing the table.
   # ########################################################################
   while (   $src_nibble_iter->more_boundaries()
          || $dst_nibble_iter->more_boundaries() ) {

      if ( $diffs ) {
         my $diff = shift @$diffs;
         if ( !$diff ) {
            MKDEBUG && _d('No more checksum diffs');
            last;
         }
         MKDEBUG && _d('Syncing checksum diff', Dumper($diff));
         $src->{tbl}->{diff} = $diff;
         $dst->{tbl}->{diff} = $diff;
      }

      my $src_chunk = $src_nibble_iter->next();
      my $dst_chunk = $dst_nibble_iter->next();
      MKDEBUG && _d('Got chunk');

      if ( $diffs
          || ($src_chunk->{cnt} || 0)  != ($dst_chunk->{cnt} || 0)
          || ($src_chunk->{crc} || '') ne ($dst_chunk->{crc} || '') ) {
         MKDEBUG && _d("Chunks differ");
         my $boundary = $src_nibble_iter->boundaries();
         foreach my $host ($src, $dst) {
            MKDEBUG && _d($host->{Cxn}->name(), $host->{rows_sth}->{Statement},
               'params:', @{$boundary->{lower}}, @{$boundary->{upper}});
            $host->{rows_sth}->execute(
               @{$boundary->{lower}}, @{$boundary->{upper}});
         }
         $row_diff->compare_sets(
            left_dbh   => $src->{Cxn}->dbh(),
            left_sth   => $src->{rows_sth},
            right_dbh  => $dst->{Cxn}->dbh(),
            right_sth  => $dst->{rows_sth},
            tbl_struct => $src->{tbl}->{tbl_struct},
            syncer     => $row_syncer,
         );
         $changer->process_rows(1, $trace);
         foreach my $host ($src, $dst) {
            $host->{rows_sth}->finish();
         }
      }

      # Get next chunks.
      $src_nibble_iter->no_more_rows();
      $dst_nibble_iter->no_more_rows();

      my $changes_dbh = $changing_src ? $src->{Cxn}->dbh()
                      :                 $dst->{Cxn}->dbh();
      $changes_dbh->commit() unless $changes_dbh->{AutoCommit};
   }

   $changer->process_rows(0, $trace);

   # Unlock the table.
   foreach my $host ($src, $dst) {
      $self->unlock(
         lock_level   => 2,
         host         => $host,
         OptionParser => $o,
      );
   }

   return $changer->get_changes();
}

sub lock_table {
   my ( $self, %args ) = @_;
   my @required_args = qw(host mode);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($host, $mode) = @args{@required_args};
   my $q   = $self->{Quoter};
   my $sql = "LOCK TABLES "
           . $q->quote(@{$host->{tbl}}{qw(db tbl)})
           . " $mode";
   MKDEBUG && _d($host->{Cxn}->name(), $sql);
   $host->{Cxn}->dbh()->do($sql);
   return;
}

# Doesn't work quite the same way as lock_and_wait. It will unlock any LOWER
# priority lock level, not just the exact same one.
sub unlock {
   my ( $self, %args ) = @_;
   my @required_args = qw(lock_level host);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($lock_level, $host) = @args{@required_args};
   my $o = $self->{OptionParser};

   my $lock = $o->get('lock');
   return unless $lock && $lock <= $lock_level;
   MKDEBUG && _d('Unlocking level', $lock);

   if ( $o->get('transaction') ) {
      MKDEBUG && _d('Committing', $host->{Cxn}->name());
      $host->{Cxn}->dbh()->commit();
   }
   else {
      my $sql = 'UNLOCK TABLES';
      MKDEBUG && _d($host->{Cxn}->name(), $sql);
      $host->{Cxn}->dbh()->do($sql);
   }

   return;
}

# Arguments:
#    lock         scalar: lock level requested by user
#    local_level  scalar: lock level code is calling from
#    src          hashref
#    dst          hashref
# Optional arguments:
#   * wait_retry_args  hashref: retry args for retrying wait/MASTER_POS_WAIT
# Lock levels:
#   0 => none
#   1 => per sync cycle
#   2 => per table
#   3 => global
# This function might actually execute the $src_sth.  If we're using
# transactions instead of table locks, the $src_sth has to be executed before
# the MASTER_POS_WAIT() on the slave.  The return value is whether the
# $src_sth was executed.
sub lock_and_wait {
   my ( $self, %args ) = @_;
   my @required_args = qw(lock_level host src);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($lock_level, $host, $src) = @args{@required_args};
   my $o = $self->{OptionParser};

   my $lock = $o->get('lock');
   return unless $lock && $lock == $lock_level;

   # First, commit/unlock the previous transaction/lock.
   if ( $o->get('transaction') ) {
      MKDEBUG && _d('Committing', $host->{Cxn}->name());
      $host->{Cxn}->dbh()->commit();
   }
   else {
      my $sql = 'UNLOCK TABLES';
      MKDEBUG && _d($host->{Cxn}->name(), $sql);
      $host->{Cxn}->dbh()->do($sql);
   }

   # Lock/start xa.
   return $host->{Cxn}->{is_source} ? $self->_lock_src(%args)
                                    : $self->_lock_dst(%args);
}

sub _lock_src {
   my ( $self, %args ) = @_;
   my @required_args = qw(lock_level host src);
   my ($lock_level, $host, $src) = @args{@required_args};
   
   my $o    = $self->{OptionParser};
   my $lock = $o->get('lock');
   MKDEBUG && _d('Locking', $host->{Cxn}->name(), 'level', $lock);

   if ( $lock == 3 ) {
      my $sql = 'FLUSH TABLES WITH READ LOCK';
      MKDEBUG && _d($host->{Cxn}->name(), $sql);
      $host->{Cxn}->dbh()->do($sql);
   }
   else {
      # Lock level 2 (per-table) or 1 (per-chunk).
      if ( $o->get('transaction') ) {
         my $sql = "START TRANSACTION /*!40108 WITH CONSISTENT SNAPSHOT */";
         MKDEBUG && _d($host->{Cxn}->name(), $sql);
         $host->{Cxn}->dbh()->do($sql);
      }
      else {
         $self->lock_table(
            host => $host,
            mode => $args{changing_src} ? 'WRITE' : 'READ',
         );
      }
   }
   return;
}

sub _lock_dst {
   my ( $self, %args ) = @_;
   my @required_args = qw(lock_level host src);
   my ($lock_level, $host, $src) = @args{@required_args};

   my $o    = $self->{OptionParser};
   my $lock = $o->get('lock');
   MKDEBUG && _d('Locking', $host->{Cxn}->name(), 'level', $lock);

   # Wait for the dest to catchup to the source, then lock the dest.
   # If there is any error beyond this point, we need to unlock/commit.
   eval {
      if ( my $timeout = $o->get('wait') ) {
         my $ms    = $self->{MasterSlave};
         my $wait;
         my $tries = $args{wait_retry_args}->{tries} || 3;
         $self->{Retry}->retry(
            tries => $tries,
            wait  => sub { sleep 5; },
            try   => sub {
               my ( %args ) = @_;
               # Be careful using $args{...} in this callback!  %args in
               # here are the passed-in args, not the args to the sub.

               if ( $args{tryno} > 1 ) {
                  warn "Retrying MASTER_POS_WAIT() for --wait $timeout...";
               }

               # Always use the misc_dbh dbh to check the master's position
               # because the main dbh might be in use due to executing
               # $src_sth.
               $wait = $ms->wait_for_master(
                  master_status => $ms->get_master_status($src->{Cxn}->aux_dbh()),
                  slave_dbh     => $host->{Cxn}->dbh(),
                  timeout       => $timeout,
               );
               if ( defined $wait->{result} && $wait->{result} != -1 ) {
                  return;  # slave caught up
               }
               die; # call fail
            },
            fail => sub {
               my (%args) = @_;
               if ( !defined $wait->{result} ) {
                  # Slave was stopped either before or during the wait.
                  # Wait a few seconds and try again in hopes that the
                  # slave is restarted.  This is the only case for which
                  # we wait and retry because the slave might have been
                  # stopped temporarily and/or unbeknownst to the user,
                  # so they'll be happy if we wait for slave to be restarted
                  # and then continue syncing.
                  my $msg;
                  if ( $wait->{waited}  ) {
                     $msg = "The slave was stopped while waiting with "
                          . "MASTER_POS_WAIT().";
                  }
                  else {
                     $msg = "MASTER_POS_WAIT() returned NULL.  Verify that "
                          . "the slave is running.";
                  }
                  if ( $tries - $args{tryno} ) {
                     $msg .= "  Sleeping $wait seconds then retrying "
                           . ($tries - $args{tryno}) . " more times.";
                  }
                  warn "$msg\n";
                  return 1; # call wait, call try
               }
               elsif ( $wait->{result} == -1 ) {
                  # MASTER_POS_WAIT timed out, don't retry since we've
                  # already waited as long as the user specified with --wait.
                  return 0;  # call final_fail
               }
            },
            final_fail => sub {
               die "Slave did not catch up to its master after $tries attempts "
                  . "of waiting $timeout seconds with MASTER_POS_WAIT.  "
                  . "Check that the slave is running, increase the --wait "
                  . "time, or disable this feature by specifying --wait 0.";
            },
         );  # retry MasterSlave::wait_for_master()
      }

      # Don't lock the destination if we're making changes on the source
      # (for sync-to-master and sync via replicate) else the destination
      # won't be apply to make the changes.
      if ( $args{changing_src} ) {
         MKDEBUG && _d('Not locking destination because changing source ',
            '(syncing via replication or sync-to-master)');
      }
      else {
         if ( $lock == 3 ) {
            my $sql = 'FLUSH TABLES WITH READ LOCK';
            MKDEBUG && _d($host->{Cxn}->name(), $sql);
            $host->{Cxn}->dbh()->do($sql);
         }
         elsif ( !$o->get('transaction') ) {
            $self->lock_table(
               host => $host,
               mode => 'READ', # $args{execute} ? 'WRITE' : 'READ')
            );
         }
      }
   };
   if ( $EVAL_ERROR ) {
      # Must abort/unlock/commit so that we don't interfere with any further
      # tables we try to do.
      foreach my $dbh ( $host->{Cxn}->dbh(), $src->{Cxn}->dbh() ) {
         MKDEBUG && _d('Caught error, unlocking/committing', $dbh);
         $dbh->do('UNLOCK TABLES');
         $dbh->commit() unless $dbh->{AutoCommit};
      }
      # ... and then re-throw the error.
      die $EVAL_ERROR;
   }

   return;
}

# This query will check all needed privileges on the table without actually
# changing anything in it.  We can't use REPLACE..SELECT because that doesn't
# work inside of LOCK TABLES.  Returns 1 if user has all needed privs to
# sync table, else returns 0.
sub have_all_privs {
   my ( $self, $dbh, $db, $tbl ) = @_;
   my $db_tbl = $self->{Quoter}->quote($db, $tbl);
   my $sql    = "SHOW FULL COLUMNS FROM $db_tbl";
   MKDEBUG && _d('Permissions check:', $sql);
   my $cols       = $dbh->selectall_arrayref($sql, {Slice => {}});
   my ($hdr_name) = grep { m/privileges/i } keys %{$cols->[0]};
   my $privs      = $cols->[0]->{$hdr_name};
   $sql = "DELETE FROM $db_tbl LIMIT 0"; # FULL COLUMNS doesn't show all privs
   MKDEBUG && _d('Permissions check:', $sql);
   eval { $dbh->do($sql); };
   my $can_delete = $EVAL_ERROR ? 0 : 1;

   MKDEBUG && _d('User privs on', $db_tbl, ':', $privs,
      ($can_delete ? 'delete' : ''));
   if ( $privs =~ m/select/ && $privs =~ m/insert/ && $privs =~ m/update/ 
        && $can_delete ) {
      MKDEBUG && _d('User has all privs');
      return 1;
   }
   MKDEBUG && _d('User does not have all privs');
   return 0;
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
# End TableSyncer package
# ###########################################################################
