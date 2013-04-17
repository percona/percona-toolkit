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
# TableSyncer package
# ###########################################################################
{
# Package: TableSyncer
# TableSyncer helps sync tables with various table sync algo modules.
package TableSyncer;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# Arguments:
#   * MasterSlave    A MasterSlave module
#   * Quoter         A Quoter module
#   * TableChecksum  A TableChecksum module
#   * Retry          A Retry module
#   * DSNParser      (optional)
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(MasterSlave Quoter TableChecksum Retry);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

# Return the first plugin from the arrayref of TableSync* plugins
# that can sync the given table struct.  plugin->can_sync() usually
# returns a hashref that it wants back when plugin->prepare_to_sync()
# is called.  Or, it may return nothing (false) to say that it can't
# sync the table.
sub get_best_plugin {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(plugins tbl_struct) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   PTDEBUG && _d('Getting best plugin');
   foreach my $plugin ( @{$args{plugins}} ) {
      PTDEBUG && _d('Trying plugin', $plugin->name);
      my ($can_sync, %plugin_args) = $plugin->can_sync(%args);
      if ( $can_sync ) {
        PTDEBUG && _d('Can sync with', $plugin->name, Dumper(\%plugin_args));
        return $plugin, %plugin_args;
      }
   }
   PTDEBUG && _d('No plugin can sync the table');
   return;
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
   my @required_args = qw(plugins src dst tbl_struct cols chunk_size
                          RowDiff ChangeHandler);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   PTDEBUG && _d('Syncing table with args:',
      map { "$_: " . Dumper($args{$_}) }
      qw(plugins src dst tbl_struct cols chunk_size));

   my ($plugins, $src, $dst, $tbl_struct, $cols, $chunk_size, $rd, $ch)
      = @args{@required_args};
   my $dp = $self->{DSNParser};
   $args{trace} = 1 unless defined $args{trace};

   if ( $args{bidirectional} && $args{ChangeHandler}->{queue} ) {
      # This should be checked by the caller but just in case...
      die "Queueing does not work with bidirectional syncing";
   }

   $args{index_hint}    = 1 unless defined $args{index_hint};
   $args{lock}        ||= 0;
   $args{wait}        ||= 0;
   $args{transaction} ||= 0;
   $args{timeout_ok}  ||= 0;

   my $q  = $self->{Quoter};

   # ########################################################################
   # Get and prepare the first plugin that can sync this table.
   # ########################################################################
   my ($plugin, %plugin_args) = $self->get_best_plugin(%args);
   die "No plugin can sync $src->{db}.$src->{tbl}" unless $plugin;

   # The row-level (state 2) checksums use __crc, so the table can't use that.
   my $crc_col = '__crc';
   while ( $tbl_struct->{is_col}->{$crc_col} ) {
      $crc_col = "_$crc_col"; # Prepend more _ until not a column.
   }
   PTDEBUG && _d('CRC column:', $crc_col);

   # Make an index hint for either the explicitly given chunk_index
   # or the chunk_index chosen by the plugin if index_hint is true.
   my $index_hint;
   if ( $args{chunk_index} ) {
      PTDEBUG && _d('Using given chunk index for index hint');
      $index_hint = "FORCE INDEX (" . $q->quote($args{chunk_index}) . ")";
   }
   elsif ( $plugin_args{chunk_index} && $args{index_hint} ) {
      PTDEBUG && _d('Using chunk index chosen by plugin for index hint');
      $index_hint = "FORCE INDEX (" . $q->quote($plugin_args{chunk_index}) . ")";
   }
   PTDEBUG && _d('Index hint:', $index_hint);

   eval {
      $plugin->prepare_to_sync(
         %args,
         %plugin_args,
         dbh        => $src->{dbh},
         db         => $src->{db},
         tbl        => $src->{tbl},
         crc_col    => $crc_col,
         index_hint => $index_hint,
      );
   };
   if ( $EVAL_ERROR ) {
      # At present, no plugin should fail to prepare, but just in case...
      die 'Failed to prepare TableSync', $plugin->name, ' plugin: ',
         $EVAL_ERROR;
   }

   # Some plugins like TableSyncChunk use checksum queries, others like
   # TableSyncGroupBy do not.  For those that do, make chunk (state 0)
   # and row (state 2) checksum queries.
   if ( $plugin->uses_checksum() ) {
      eval {
         my ($chunk_sql, $row_sql) = $self->make_checksum_queries(%args);
         $plugin->set_checksum_queries($chunk_sql, $row_sql);
      };
      if ( $EVAL_ERROR ) {
         # This happens if src and dst are really different and the same
         # checksum algo and hash func can't be used on both.
         die "Failed to make checksum queries: $EVAL_ERROR";
      }
   } 

   # ########################################################################
   # Plugin is ready, return now if this is a dry run.
   # ########################################################################
   if ( $args{dry_run} ) {
      return $ch->get_changes(), ALGORITHM => $plugin->name;
   }

   # ########################################################################
   # Start syncing the table.
   # ########################################################################

   # USE db on src and dst for cases like when replicate-do-db is being used.
   eval {
      $src->{dbh}->do("USE `$src->{db}`");
      $dst->{dbh}->do("USE `$dst->{db}`");
   };
   if ( $EVAL_ERROR ) {
      # This shouldn't happen, but just in case.  (The db and tbl on src
      # and dst should be checked before calling this sub.)
      die "Failed to USE database on source or destination: $EVAL_ERROR";
   }

   # For bidirectional syncing it's important to know on which dbh
   # changes are made or rows are fetched.  This identifies the dbhs,
   # then you can search for each one by its address like
   # "dbh DBI::db=HASH(0x1028b38)".
   PTDEBUG && _d('left dbh', $src->{dbh});
   PTDEBUG && _d('right dbh', $dst->{dbh});

   chomp(my $hostname = `hostname`);
   my $trace_msg
      = $args{trace} ? "src_db:$src->{db} src_tbl:$src->{tbl} "
         . ($dp && $src->{dsn} ? "src_dsn:".$dp->as_string($src->{dsn}) : "")
         . " dst_db:$dst->{db} dst_tbl:$dst->{tbl} "
         . ($dp && $dst->{dsn} ? "dst_dsn:".$dp->as_string($dst->{dsn}) : "")
         . " " . join(" ", map { "$_:" . ($args{$_} || 0) }
                     qw(lock transaction changing_src replicate bidirectional))
         . " pid:$PID "
         . ($ENV{USER} ? "user:$ENV{USER} " : "")
         . ($hostname  ? "host:$hostname"   : "")
      :                "";
   PTDEBUG && _d("Binlog trace message:", $trace_msg);

   $self->lock_and_wait(%args, lock_level => 2);  # per-table lock

   my $callback = $args{callback};
   my $cycle    = 0;
   while ( !$plugin->done() ) {

      # Do as much of the work as possible before opening a transaction or
      # locking the tables.
      PTDEBUG && _d('Beginning sync cycle', $cycle);
      my $src_sql = $plugin->get_sql(
         database => $src->{db},
         table    => $src->{tbl},
         where    => $args{where},
      );
      my $dst_sql = $plugin->get_sql(
         database => $dst->{db},
         table    => $dst->{tbl},
         where    => $args{where},
      );

      if ( $args{transaction} ) {
         if ( $args{bidirectional} ) {
            # Making changes on src and dst.
            $src_sql .= ' FOR UPDATE';
            $dst_sql .= ' FOR UPDATE';
         }
         elsif ( $args{changing_src} ) {
            # Making changes on master (src) which replicate to slave (dst).
            $src_sql .= ' FOR UPDATE';
            $dst_sql .= ' LOCK IN SHARE MODE';
         }
         else {
            # Making changes on slave (dst).
            $src_sql .= ' LOCK IN SHARE MODE';
            $dst_sql .= ' FOR UPDATE';
         }
      }
      PTDEBUG && _d('src:', $src_sql);
      PTDEBUG && _d('dst:', $dst_sql);

      # Give callback a chance to do something with the SQL statements.
      $callback->($src_sql, $dst_sql) if $callback;

      # Prepare each host for next sync cycle. This does stuff
      # like reset/init MySQL accumulator vars, etc.
      $plugin->prepare_sync_cycle($src);
      $plugin->prepare_sync_cycle($dst);

      # Prepare SQL statements on host.  These aren't real prepared
      # statements (i.e. no ? placeholders); we just need sths to
      # pass to compare_sets().  Also, we can control buffering
      # (mysql_use_result) on the sths.
      my $src_sth = $src->{dbh}->prepare($src_sql);
      my $dst_sth = $dst->{dbh}->prepare($dst_sql);
      if ( $args{buffer_to_client} ) {
         $src_sth->{mysql_use_result} = 1;
         $dst_sth->{mysql_use_result} = 1;
      }

      # The first cycle should lock to begin work; after that, unlock only if
      # the plugin says it's OK (it may want to dig deeper on the rows it
      # currently has locked).
      my $executed_src = 0;
      if ( !$cycle || !$plugin->pending_changes() ) {
         # per-sync cycle lock
         $executed_src
            = $self->lock_and_wait(%args, src_sth => $src_sth, lock_level => 1);
      }

      # The source sth might have already been executed by lock_and_wait().
      $src_sth->execute() unless $executed_src;
      $dst_sth->execute();

      # Compare rows in the two sths.  If any differences are found
      # (same_row, not_in_left, not_in_right), the appropriate $syncer
      # methods are called to handle them.  Changes may be immediate, or...
      $rd->compare_sets(
         left_sth   => $src_sth,
         right_sth  => $dst_sth,
         left_dbh   => $src->{dbh},
         right_dbh  => $dst->{dbh},
         syncer     => $plugin,
         tbl_struct => $tbl_struct,
      );
      # ...changes may be queued and executed now.
      $ch->process_rows(1, $trace_msg);

      PTDEBUG && _d('Finished sync cycle', $cycle);
      $cycle++;
   }

   $ch->process_rows(0, $trace_msg);

   $self->unlock(%args, lock_level => 2);

   return $ch->get_changes(), ALGORITHM => $plugin->name;
}

sub make_checksum_queries {
   my ( $self, %args ) = @_;
   my @required_args = qw(src dst tbl_struct);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($src, $dst, $tbl_struct) = @args{@required_args};
   my $checksum = $self->{TableChecksum};

   # Decide on checksumming strategy and store checksum query prototypes for
   # later.
   my $src_algo = $checksum->best_algorithm(
      algorithm => 'BIT_XOR',
      dbh       => $src->{dbh},
      where     => 1,
      chunk     => 1,
      count     => 1,
   );
   my $dst_algo = $checksum->best_algorithm(
      algorithm => 'BIT_XOR',
      dbh       => $dst->{dbh},
      where     => 1,
      chunk     => 1,
      count     => 1,
   );
   if ( $src_algo ne $dst_algo ) {
      die "Source and destination checksum algorithms are different: ",
         "$src_algo on source, $dst_algo on destination"
   }
   PTDEBUG && _d('Chosen algo:', $src_algo);

   my $src_func = $checksum->choose_hash_func(dbh => $src->{dbh}, %args);
   my $dst_func = $checksum->choose_hash_func(dbh => $dst->{dbh}, %args);
   if ( $src_func ne $dst_func ) {
      die "Source and destination hash functions are different: ",
      "$src_func on source, $dst_func on destination";
   }
   PTDEBUG && _d('Chosen hash func:', $src_func);

   # Since the checksum algo and hash func are the same on src and dst
   # it doesn't matter if we use src_algo/func or dst_algo/func.

   my $crc_wid    = $checksum->get_crc_wid($src->{dbh}, $src_func);
   my ($crc_type) = $checksum->get_crc_type($src->{dbh}, $src_func);
   my $opt_slice;
   if ( $src_algo eq 'BIT_XOR' && $crc_type !~ m/int$/ ) {
      $opt_slice = $checksum->optimize_xor(
         dbh      => $src->{dbh},
         function => $src_func
      );
   }

   my $chunk_sql = $checksum->make_checksum_query(
      %args,
      db        => $src->{db},
      tbl       => $src->{tbl},
      algorithm => $src_algo,
      function  => $src_func,
      crc_wid   => $crc_wid,
      crc_type  => $crc_type,
      opt_slice => $opt_slice,
      replicate => undef, # replicate means something different to this sub
   );                     # than what we use it for; do not pass it!
   PTDEBUG && _d('Chunk sql:', $chunk_sql);
   my $row_sql = $checksum->make_row_checksum(
      %args,
      function => $src_func,
   );
   PTDEBUG && _d('Row sql:', $row_sql);
   return $chunk_sql, $row_sql;
}

sub lock_table {
   my ( $self, $dbh, $where, $db_tbl, $mode ) = @_;
   my $query = "LOCK TABLES $db_tbl $mode";
   PTDEBUG && _d($query);
   $dbh->do($query);
   PTDEBUG && _d('Acquired table lock on', $where, 'in', $mode, 'mode');
}

# Doesn't work quite the same way as lock_and_wait. It will unlock any LOWER
# priority lock level, not just the exact same one.
sub unlock {
   my ( $self, %args ) = @_;

   foreach my $arg ( qw(src dst lock transaction lock_level) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $src = $args{src};
   my $dst = $args{dst};

   return unless $args{lock} && $args{lock} <= $args{lock_level};

   # First, unlock/commit.
   foreach my $dbh ( $src->{dbh}, $dst->{dbh} ) {
      if ( $args{transaction} ) {
         PTDEBUG && _d('Committing', $dbh);
         $dbh->commit();
      }
      else {
         my $sql = 'UNLOCK TABLES';
         PTDEBUG && _d($dbh, $sql);
         $dbh->do($sql);
      }
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
   my $result = 0;

   foreach my $arg ( qw(src dst lock lock_level) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $src = $args{src};
   my $dst = $args{dst};

   return unless $args{lock} && $args{lock} == $args{lock_level};
   PTDEBUG && _d('lock and wait, lock level', $args{lock});

   # First, commit/unlock the previous transaction/lock.
   foreach my $dbh ( $src->{dbh}, $dst->{dbh} ) {
      if ( $args{transaction} ) {
         PTDEBUG && _d('Committing', $dbh);
         $dbh->commit();
      }
      else {
         my $sql = 'UNLOCK TABLES';
         PTDEBUG && _d($dbh, $sql);
         $dbh->do($sql);
      }
   }

   # User wants us to lock for consistency.  But lock only on source initially;
   # might have to wait for the slave to catch up before locking on the dest.
   if ( $args{lock} == 3 ) {
      my $sql = 'FLUSH TABLES WITH READ LOCK';
      PTDEBUG && _d($src->{dbh}, $sql);
      $src->{dbh}->do($sql);
   }
   else {
      # Lock level 2 (per-table) or 1 (per-sync cycle)
      if ( $args{transaction} ) {
         if ( $args{src_sth} ) {
            # Execute the $src_sth on the source, so LOCK IN SHARE MODE/FOR
            # UPDATE will lock the rows examined.
            PTDEBUG && _d('Executing statement on source to lock rows');

            my $sql = "START TRANSACTION /*!40108 WITH CONSISTENT SNAPSHOT */";
            PTDEBUG && _d($src->{dbh}, $sql);
            $src->{dbh}->do($sql);

            $args{src_sth}->execute();
            $result = 1;
         }
      }
      else {
         $self->lock_table($src->{dbh}, 'source',
            $self->{Quoter}->quote($src->{db}, $src->{tbl}),
            $args{changing_src} ? 'WRITE' : 'READ');
      }
   }

   # If there is any error beyond this point, we need to unlock/commit.
   eval {
      if ( my $timeout = $args{wait} ) {
         my $ms    = $self->{MasterSlave};
         my $tries = $args{wait_retry_args}->{tries} || 3;
         my $wait;
         my $sleep = $args{wait_retry_args}->{wait}  || 10;
         $self->{Retry}->retry(
            tries => $tries,
            wait  => sub { sleep($sleep) },
            try   => sub {
               my ( %args ) = @_;
               # Be careful using $args{...} in this callback!  %args in
               # here are the passed-in args, not the args to lock_and_wait().

               if ( $args{tryno} > 1 ) {
                  warn "Retrying MASTER_POS_WAIT() for --wait $timeout...";
               }

               # Always use the misc_dbh dbh to check the master's position
               # because the main dbh might be in use due to executing
               # $src_sth.
               $wait = $ms->wait_for_master(
                  master_status => $ms->get_master_status($src->{misc_dbh}),
                  slave_dbh     => $dst->{dbh},
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
                     $msg .= "  Sleeping $sleep seconds then retrying "
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
         PTDEBUG && _d('Not locking destination because changing source ',
            '(syncing via replication or sync-to-master)');
      }
      else {
         if ( $args{lock} == 3 ) {
            my $sql = 'FLUSH TABLES WITH READ LOCK';
            PTDEBUG && _d($dst->{dbh}, ',', $sql);
            $dst->{dbh}->do($sql);
         }
         elsif ( !$args{transaction} ) {
            $self->lock_table($dst->{dbh}, 'dest',
               $self->{Quoter}->quote($dst->{db}, $dst->{tbl}),
               $args{execute} ? 'WRITE' : 'READ');
         }
      }
   };
   if ( $EVAL_ERROR ) {
      # Must abort/unlock/commit so that we don't interfere with any further
      # tables we try to do.
      if ( $args{src_sth}->{Active} ) {
         $args{src_sth}->finish();
      }
      foreach my $dbh ( $src->{dbh}, $dst->{dbh}, $src->{misc_dbh} ) {
         next unless $dbh;
         PTDEBUG && _d('Caught error, unlocking/committing on', $dbh);
         $dbh->do('UNLOCK TABLES');
         $dbh->commit() unless $dbh->{AutoCommit};
      }
      # ... and then re-throw the error.
      die $EVAL_ERROR;
   }

   return $result;
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
