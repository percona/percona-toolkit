# This program is copyright 2011 Percona Inc.
# This program is copyright 2009-2010 Baron Schwartz.
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
# InnoDBStatusParser package $Revision: 7096 $
# ###########################################################################
{
# Package: InnoDBStatusParser
# InnoDBStatusParser parses SHOW INNODB STATUS.
package InnoDBStatusParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# TODO see 3 tablespace extents now reserved for B-tree split operations
# example in note on case 1028

# Some common patterns
my $d  = qr/(\d+)/;                    # Digit
my $f  = qr/(\d+\.\d+)/;               # Float
my $t  = qr/(\d+ \d+)/;                # Transaction ID
my $i  = qr/((?:\d{1,3}\.){3}\d+)/;    # IP address
my $n  = qr/([^`\s]+)/;                # MySQL object name
my $w  = qr/(\w+)/;                    # Words
my $fl = qr/([\w\.\/]+) line $d/;      # Filename and line number
my $h  = qr/((?:0x)?[0-9a-f]*)/;       # Hex
my $s  = qr/(\d{6} .\d:\d\d:\d\d)/;    # InnoDB timestamp

sub ts_to_time {
   my ( $ts ) = @_;
   sprintf('200%d-%02d-%02d %02d:%02d:%02d',
      $ts =~ m/(\d\d)(\d\d)(\d\d) +(\d+):(\d+):(\d+)/);
}

# A thread's proc_info can be at least 98 different things I've found in the
# source.  Fortunately, most of them begin with a gerunded verb.  These are
# the ones that don't.
my %is_proc_info = (
   'After create'                 => 1,
   'Execution of init_command'    => 1,
   'FULLTEXT initialization'      => 1,
   'Reopen tables'                => 1,
   'Repair done'                  => 1,
   'Repair with keycache'         => 1,
   'System lock'                  => 1,
   'Table lock'                   => 1,
   'Thread initialized'           => 1,
   'User lock'                    => 1,
   'copy to tmp table'            => 1,
   'discard_or_import_tablespace' => 1,
   'end'                          => 1,
   'got handler lock'             => 1,
   'got old table'                => 1,
   'init'                         => 1,
   'key cache'                    => 1,
   'locks'                        => 1,
   'malloc'                       => 1,
   'query end'                    => 1,
   'rename result table'          => 1,
   'rename'                       => 1,
   'setup'                        => 1,
   'statistics'                   => 1,
   'status'                       => 1,
   'table cache'                  => 1,
   'update'                       => 1,
);

# Each parse rule is a set of rules and some custom code.  Each rule is an
# arrayref of arrayrefs of columns and a regular expression pattern, to be
# matched with the 'm' flag.
# A lot of variables are also exported to SHOW STATUS.  I have named them the
# same where possible, by comparing the sources in srv_export_innodb_status()
# and looking at where the InnoDB status is printed from.
my ( $COLS, $PATTERN ) = (0, 1);
my %parse_rules_for = (

   # Google patches
   "BACKGROUND THREAD" => {
      rules => [
         [
            [qw(
               Innodb_srv_main_1_second_loops
               Innodb_srv_main_sleeps
               Innodb_srv_main_10_second_loops
               Innodb_srv_main_background_loops
               Innodb_srv_main_flush_loops
            )],
            qr/^srv_master_thread loops: $d 1_second, $d sleeps, $d 10_second, $d background, $d flush$/m,
         ],
         [
            [qw(
               Innodb_srv_sync_flush
               Innodb_srv_async_flush
            )],
            qr/^srv_master_thread log flush: $d sync, $d async$/m,
         ],
         [
            [qw(
               Innodb_flush_from_dirty_buffer
               Innodb_flush_from_other
               Innodb_flush_from_checkpoint
               Innodb_flush_from_log_io_complete
               Innodb_flush_from_log_write_up_to
               Innodb_flush_from_archive
            )],
            qr/^fsync callers: $d buffer pool, $d other, $d checkpoint, $d log aio, $d log sync, $d archive$/m,
         ],
      ],
      customcode => sub{},
   },

   "SEMAPHORES" => {
      rules => [
         # Google patches
         [
            [qw(
               Innodb_lock_wait_timeouts
            )],
            qr/^Lock wait timeouts $d$/m,
         ],
         [
            [qw(
               Innodb_wait_array_reservation_count
               Innodb_wait_array_signal_count
            )],
            qr/^OS WAIT ARRAY INFO: reservation count $d, signal count $d$/m,
         ],
         [
            [qw(
               Innodb_mutex_spin_waits
               Innodb_mutex_spin_rounds
               Innodb_mutex_os_waits
            )],
            qr/^Mutex spin waits $d, rounds $d, OS waits $d$/m,
         ],
         [
            [qw(
               Innodb_mutex_rw_shared_spins
               Innodb_mutex_rw_shared_os_waits
               Innodb_mutex_rw_excl_spins
               Innodb_mutex_rw_excl_os_waits
            )],
            qr/^RW-shared spins $d, OS waits $d; RW-excl spins $d, OS waits $d$/m,
         ],
      ],
      customcode => sub {},
   },

   'LATEST FOREIGN KEY ERROR' => {
      rules => [
         [
            [qw(
               Innodb_fk_time
            )],
            qr/^$s/m,
         ],
         [
            [qw(
               Innodb_fk_child_db
               Innodb_fk_child_table
            )],
            qr{oreign key constraint (?:fails for|of) table `?(.*?)`?/`?(.*?)`?:$}m,
         ],
         [
            [qw(
               Innodb_fk_name
               Innodb_fk_child_cols
               Innodb_fk_parent_db
               Innodb_fk_parent_table
               Innodb_fk_parent_cols
            )],
            qr/CONSTRAINT `?$n`? FOREIGN KEY \((.+?)\) REFERENCES (?:`?$n`?\.)?`?$n`? \((.+?)\)/m,
         ],
         [
            [qw(
               Innodb_fk_child_index
            )],
            qr/(?:in child table, in index|foreign key in table is) `?$n`?/m,
         ],
         [
            [qw(
               Innodb_fk_parent_index
            )],
            qr/in parent table \S+ in index `$n`/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         if ( $status->{Innodb_fk_time} ) {
            $status->{Innodb_fk_time} = ts_to_time($status->{Innodb_fk_time});
         }
         $status->{Innodb_fk_parent_db} ||= $status->{Innodb_fk_child_db};
         if ( $text =~ m/^there is no index/m ) {
            $status->{Innodb_fk_reason} = 'No index or type mismatch';
         }
         elsif ( $text =~ m/closest match we can find/ ) {
            $status->{Innodb_fk_reason} = 'No matching row';
         }
         elsif ( $text =~ m/, there is a record/ ) {
            $status->{Innodb_fk_reason} = 'Orphan row';
         }
         elsif ( $text =~ m/Cannot resolve table name|nor its .ibd file/ ) {
            $status->{Innodb_fk_reason} = 'No such parent table';
         }
         elsif ( $text =~ m/Cannot (?:DISCARD|drop)/ ) {
            $status->{Innodb_fk_reason} = 'Table is referenced';
            @{$status}{qw(
               Innodb_fk_parent_db Innodb_fk_parent_table
               Innodb_fk_child_db Innodb_fk_child_table
            )}
            = $text =~ m{table `$n/$n`\nbecause it is referenced by `$n/$n`};
         }
      },
   },

   'LATEST DETECTED DEADLOCK' => {
      rules => [
         [
            [qw(
               Innodb_deadlock_time
            )],
            qr/^$s$/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         if ( $status->{Innodb_deadlock_time} ) {
            $status->{Innodb_deadlock_time}
               = ts_to_time($status->{Innodb_deadlock_time});
         }
      },
   },

   'TRANSACTIONS' => {
      rules => [
         [
            [qw(Innodb_transaction_counter)],
            qr/^Trx id counter $t$/m,
         ],
         [
            [qw(
               Innodb_purged_to
               Innodb_undo_log_record
            )],
            qr/^Purge done for trx's n:o < $t undo n:o < $t$/m,
         ],
         [
            [qw(Innodb_history_list_length)],
            qr/^History list length $d$/m,
         ],
         [
            [qw(Innodb_lock_struct_count)],
            qr/^Total number of lock structs in row lock hash table $d$/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         $status->{Innodb_transactions_truncated}
            = $text =~ m/^\.\.\. truncated\.\.\.$/m ? 1 : 0;
         my @txns = $text =~ m/(^---TRANSACTION)/mg;
         $status->{Innodb_transactions} = scalar(@txns);
      },
   },

   # See os_aio_print() in os0file.c
   'FILE I/O' => {
      rules => [
         [
            [qw(
               Innodb_pending_aio_reads
               Innodb_pending_aio_writes
            )],
            qr/^Pending normal aio reads: $d, aio writes: $d,$/m,
         ],
         [
            [qw(
               Innodb_insert_buffer_pending_reads
               Innodb_log_pending_io
               Innodb_pending_sync_io
            )],
            qr{^ ibuf aio reads: $d, log i/o's: $d, sync i/o's: $d$}m,
         ],
         [
            [qw(
               Innodb_os_log_pending_fsyncs
               Innodb_buffer_pool_pending_fsyncs
            )],
            qr/^Pending flushes \(fsync\) log: $d; buffer pool: $d$/m,
         ],
         [
            [qw(
               Innodb_data_reads
               Innodb_data_writes
               Innodb_data_fsyncs
            )],
            qr/^$d OS file reads, $d OS file writes, $d OS fsyncs$/m,
         ],
         [
            [qw(
               Innodb_data_reads_sec
               Innodb_data_bytes_per_read
               Innodb_data_writes_sec
               Innodb_data_fsyncs_sec
            )],
            qr{^$f reads/s, $d avg bytes/read, $f writes/s, $f fsyncs/s$}m,
         ],
         [
            [qw(
               Innodb_data_pending_preads
               Innodb_data_pending_pwrites
            )],
            qr/$d pending preads, $d pending pwrites$/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         my @thds = $text =~ m/^I.O thread $d state:/gm;
         $status->{Innodb_num_io_threads} = scalar(@thds);
         # To match the output of SHOW STATUS:
         $status->{Innodb_data_pending_fsyncs}
            = $status->{Innodb_os_log_pending_fsyncs}
            + $status->{Innodb_buffer_pool_pending_fsyncs};
      },
   },

   # See srv_printf_innodb_monitor() in storage/innobase/srv/srv0srv.c and
   # ibuf_print() in storage/innobase/ibuf/ibuf0ibuf.c
   'INSERT BUFFER AND ADAPTIVE HASH INDEX' => {
      rules => [
         [
            [qw(
               Innodb_insert_buffer_size
               Innodb_insert_buffer_free_list_length
               Innodb_insert_buffer_segment_size
            )],
            qr/^Ibuf(?: for space 0)?: size $d, free list len $d, seg size $d,$/m,
         ],
         [
            [qw(
               Innodb_insert_buffer_inserts
               Innodb_insert_buffer_merged_records
               Innodb_insert_buffer_merges
            )],
            qr/^$d inserts, $d merged recs, $d merges$/m,
         ],
         [
            [qw(
               Innodb_hash_table_size
               Innodb_hash_table_used_cells
               Innodb_hash_table_buf_frames_reserved
            )],
            qr/^Hash table size $d, used cells $d, node heap has $d buffer\(s\)$/m,
         ],
         [
            [qw(
               Innodb_hash_searches_sec
               Innodb_nonhash_searches_sec
            )],
            qr{^$f hash searches/s, $f non-hash searches/s$}m,
         ],
      ],
      customcode => sub {},
   },

   # See log_print() in storage/innobase/log/log0log.c
   'LOG' => {
      rules => [
         [
            [qw(
               Innodb_log_sequence_no
            )],
            qr/Log sequence number \s*(\d.*)$/m,
         ],
         [
            [qw(
               Innodb_log_flushed_to
            )],
            qr/Log flushed up to \s*(\d.*)$/m,
         ],
         [
            [qw(
               Innodb_log_last_checkpoint
            )],
            qr/Last checkpoint at \s*(\d.*)$/m,
         ],
         [
            [qw(
               Innodb_log_pending_writes
               Innodb_log_pending_chkp_writes
            )],
            qr/$d pending log writes, $d pending chkp writes/m,
         ],
         [
            [qw(
               Innodb_log_ios
               Innodb_log_ios_sec
            )],
            qr{$d log i/o's done, $f log i/o's/second}m,
         ],
         # Google patches
         [
            [qw(
               Innodb_log_caller_write_buffer_pool
               Innodb_log_caller_write_background_sync
               Innodb_log_caller_write_background_async
               Innodb_log_caller_write_internal
               Innodb_log_caller_write_checkpoint_sync
               Innodb_log_caller_write_checkpoint_async
               Innodb_log_caller_write_log_archive
               Innodb_log_caller_write_commit_sync
               Innodb_log_caller_write_commit_async
            )],
            qr/^log sync callers: $d buffer pool, background $d sync and $d async, $d internal, checkpoint $d sync and $d async, $d archive, commit $d sync and $d async$/m,
         ],
         [
            [qw(
               Innodb_log_syncer_write_buffer_pool
               Innodb_log_syncer_write_background_sync
               Innodb_log_syncer_write_background_async
               Innodb_log_syncer_write_internal
               Innodb_log_syncer_write_checkpoint_sync
               Innodb_log_syncer_write_checkpoint_async
               Innodb_log_syncer_write_log_archive
               Innodb_log_syncer_write_commit_sync
               Innodb_log_syncer_write_commit_async
            )],
            qr/^log sync syncers: $d buffer pool, background $d sync and $d async, $d internal, checkpoint $d sync and $d async, $d archive, commit $d sync and $d async$/m,
         ],
      ],
      customcode => sub {},
   },

   # See srv_printf_innodb_monitor().
   'BUFFER POOL AND MEMORY' => {
      rules => [
         [
            [qw(
               Innodb_total_memory_allocated
               Innodb_common_memory_allocated
            )],
            qr/^Total memory allocated $d; in additional pool allocated $d$/m,
         ],
         [
            [qw(
               Innodb_dictionary_memory_allocated
            )],
            qr/Dictionary memory allocated $d/m,
         ],
         [
            [qw(
               Innodb_awe_memory_allocated
            )],
            qr/$d MB of AWE memory/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_awe_memory_frames
            )],
            qr/AWE: Buffer pool memory frames\s+$d/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_awe_mapped
            )],
            qr/AWE: Database pages and free buffers mapped in frames\s+$d/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pages_total
            )],
            qr/^Buffer pool size\s*$d$/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pages_free
            )],
            qr/^Free buffers\s*$d$/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pages_data
            )],
            qr/^Database pages\s*$d$/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pages_dirty
            )],
            qr/^Modified db pages\s*$d$/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pending_reads
            )],
            qr/^Pending reads $d$/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pending_data_writes
               Innodb_buffer_pool_pending_dirty_writes
               Innodb_buffer_pool_pending_single_writes
            )],
            qr/Pending writes: LRU $d, flush list $d, single page $d/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pages_read
               Innodb_buffer_pool_pages_created
               Innodb_buffer_pool_pages_written
            )],
            qr/^Pages read $d, created $d, written $d$/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pages_read_sec
               Innodb_buffer_pool_pages_created_sec
               Innodb_buffer_pool_pages_written_sec
            )],
            qr{^$f reads/s, $f creates/s, $f writes/s$}m,
         ],
         [
            [qw(
               Innodb_buffer_pool_awe_pages_remapped_sec
            )],
            qr{^AWE: $f page remaps/s$}m,
         ],
         [
            [qw(
               Innodb_buffer_pool_hit_rate
            )],
            qr/^Buffer pool hit rate $d/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         if ( defined $status->{Innodb_buffer_pool_hit_rate} ) {
            $status->{Innodb_buffer_pool_hit_rate} /= 1000;
         }
         else {
            $status->{Innodb_buffer_pool_hit_rate} = 1;
         }
      },
   },

   'ROW OPERATIONS' => {
      rules => [
         [
            [qw(
               Innodb_threads_inside_kernel
               Innodb_threads_queued
            )],
            qr/^$d queries inside InnoDB, $d queries in queue$/m,
         ],
         [
            [qw(
               Innodb_read_views_open
            )],
            qr/^$d read views open inside InnoDB$/m,
         ],
         [
            [qw(
               Innodb_reserved_extent_count
            )],
            qr/^$d tablespace extents now reserved for B-tree/m,
         ],
         [
            [qw(
               Innodb_main_thread_proc_no
               Innodb_main_thread_id
               Innodb_main_thread_state
            )],
            qr/^Main thread (?:process no. $d, )?id $d, state: (.*)$/m,
         ],
         [
            [qw(
               Innodb_rows_inserted
               Innodb_rows_updated
               Innodb_rows_deleted
               Innodb_rows_read
            )],
            qr/^Number of rows inserted $d, updated $d, deleted $d, read $d$/m,
         ],
         [
            [qw(
               Innodb_rows_inserted_sec
               Innodb_rows_updated_sec
               Innodb_rows_deleted_sec
               Innodb_rows_read_sec
            )],
            qr{^$f inserts/s, $f updates/s, $f deletes/s, $f reads/s$}m,
         ],
      ],
      customcode => sub {},
   },

   top_level => {
      rules => [
         [
            [qw(
               Innodb_status_time
            )],
            qr/^$s INNODB MONITOR OUTPUT$/m,
         ],
         [
            [qw(
               Innodb_status_interval
            )],
            qr/Per second averages calculated from the last $d seconds/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         $status->{Innodb_status_time}
            = ts_to_time($status->{Innodb_status_time});
         $status->{Innodb_status_truncated}
            = $text =~ m/END OF INNODB MONITOR OUTPUT/ ? 0 : 1;
      },
   },

   transaction => {
      rules => [
         [
            [qw(
               txn_id
               txn_status
               active_secs
               proc_no
               os_thread_id
            )],
            qr/^(?:---)?TRANSACTION $t, (\D*?)(?: $d sec)?, (?:process no $d, )?OS thread id $d/m,
         ],
         [
            [qw(
               thread_status
               tickets
            )],
            qr/OS thread id \d+(?: ([^,]+?))?(?:, thread declared inside InnoDB $d)?$/m,
         ],
         [
            [qw(
               txn_query_status
               lock_structs
               heap_size
               row_locks
               undo_log_entries
            )],
            qr/^(?:(\D*) )?$d lock struct\(s\), heap size $d(?:, $d row lock\(s\))?(?:, undo log entries $d)?$/m,
         ],
         [
            [qw(
               lock_wait_time
            )],
            qr/^------- TRX HAS BEEN WAITING $d SEC/m,
         ],
         [
            [qw(
               mysql_tables_used
               mysql_tables_locked
            )],
            qr/^mysql tables in use $d, locked $d$/m,
         ],
         [
            [qw(
               read_view_lower_limit
               read_view_upper_limit
            )],
            qr/^Trx read view will not see trx with id >= $t, sees < $t$/m,
         ],
         # Only a certain number of bytes of the query text are included, at least
         # under some circumstances.  Some versions include 300, some 600, some
         # 3100.
         [
            [qw(
               query_text
            )],
            qr{
               ^MySQL\sthread\sid\s[^\n]+\n           # This comes before the query text
               (.*?)                                  # The query text
               (?=                                    # Followed by any of...
                  ^Trx\sread\sview
                  |^-------\sTRX\sHAS\sBEEN\sWAITING
                  |^TABLE\sLOCK
                  |^RECORD\sLOCKS\sspace\sid
                  |^(?:---)?TRANSACTION
                  |^\*\*\*\s\(\d\)
                  |\Z
               )
            }xms,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         if ( $status->{query_text} ) {
            $status->{query_text} =~ s/\n*$//;
         }
      },
   },

   lock => {
      rules => [
         [
            [qw(
               type space_id page_no num_bits index database table txn_id mode
            )],
            qr{^(RECORD|TABLE) LOCKS? (?:space id $d page no $d n bits $d index `?$n`? of )?table `$n(?:/|`\.`)$n` trx id $t lock.mode (\S+)}m,
         ],
         [
            [qw(
               gap
            )],
            qr/^(?:RECORD|TABLE) .*? locks (rec but not gap|gap before rec)/m,
         ],
         [
            [qw(
               insert_intent
            )],
            qr/^(?:RECORD|TABLE) .*? (insert intention)/m,
         ],
         [
            [qw(
               waiting
            )],
            qr/^(?:RECORD|TABLE) .*? (waiting)/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
      },
   },

   io_thread => {
      rules => [
         [
            [qw(
               id
               state
               purpose

               event_set
            )],
            qr{^I/O thread $d state: (.+?) \((.*)\)}m,
         ],
         # Support for Google patches
         [
            [qw(
               io_reads
               io_writes
               io_requests
               io_wait
               io_avg_wait
               max_io_wait
            )],
            qr{reads $d writes $d requests $d io secs $f io msecs/request $f max_io_wait $f}m,
         ],
         [
            [qw(
               event_set
            )],
            qr/ ev (set)/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
      },
   },

   # Depending on whether it's a SYNC_MUTEX,RW_LOCK_EX,RW_LOCK_SHARED,
   # there will be different text output
   # See sync_array_cell_print() in innobase/sync/sync0arr.c
   mutex_wait => {
      rules => [
         [
            [qw(
               thread_id
               mutex_file
               mutex_line
               wait_secs
            )],
            qr/^--Thread $d has waited at $fl for $f seconds/m,
         ],
         [
            [qw(
               wait_has_ended
            )],
            qr/^wait has ended$/m,
         ],
         [
            [qw(
               cell_event_set
            )],
            qr/^wait is ending$/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         if ( $text =~ m/^Mutex at/m ) {
            InnoDBParser::apply_rules(undef, $status, $text, 'sync_mutex');
         }
         else {
            InnoDBParser::apply_rules(undef, $status, $text, 'rw_lock');
         }
      },
   },

   sync_mutex => {
      rules => [
         [
            [qw(
               type 
               lock_mem_addr
               lock_cfile_name
               lock_cline
               lock_word
            )],
            qr/^(M)utex at $h created file $fl, lock var $d$/m,
         ],
         [
            [qw(
               lock_file_name
               lock_file_line
               num_waiters
            )],
            qr/^(?:Last time reserved in file $fl, )?waiters flag $d$/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
      },
   },

   rw_lock => {
      rules => [
         [
            [qw(
               type 
               lock_cfile_name
               lock_cline
            )],
            qr/^(.)-lock on RW-latch at $h created in file $fl$/m,
         ],
         [
            [qw(
               writer_thread
               writer_lock_mode
            )],
            qr/^a writer \(thread id $d\) has reserved it in mode  (.*)$/m,
         ],
         [
            [qw(
               num_readers
               num_waiters
            )],
            qr/^number of readers $d, waiters flag $d$/m,
         ],
         [
            [qw(
               last_s_file_name
               last_s_line
            )],
            qr/^Last time read locked in file $fl$/m,
         ],
         [
            [qw(
               last_x_file_name
               last_x_line
            )],
            qr/^Last time write locked in file $fl$/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
      },
   },

);

sub new {
   my ( $class, %args ) = @_;
   return bless {}, $class;
}

sub parse {
   my ( $self, $text ) = @_;

   # This will end up holding a series of "tables."
   my %result = (
      status                => [{}], # Non-repeating data
      deadlock_transactions => [],   # The transactions only
      deadlock_locks        => [],   # Both held and waited-for
      transactions          => [],
      transaction_locks     => [],   # Both held and waited-for
      io_threads            => [],
      mutex_waits           => [],
      insert_buffer_pages   => [],   # Only if InnoDB built with UNIV_IBUF_DEBUG
   );
   my $status = $result{status}[0];

   # Split it into sections and stash for parsing.
   my %innodb_sections;
   my @matches = $text
      =~ m#\n(---+)\n([A-Z /]+)\n\1\n(.*?)(?=\n(---+)\n[A-Z /]+\n\4\n|$)#gs;
   while ( my ($start, $name, $section_text, $end) = splice(@matches, 0, 4) ) {
      $innodb_sections{$name} = $section_text;
   }

   # Get top-level info about the status which isn't included in any subsection.
   $self->apply_rules($status, $text, 'top_level');

   # Parse non-nested data in each subsection.
   foreach my $section ( keys %innodb_sections ) {
      my $section_text = $innodb_sections{$section};
      next unless defined $section_text; # No point in trying to parse further.
      $self->apply_rules($status, $section_text, $section);
   }

   # Now get every other table.
   if ( $innodb_sections{'LATEST DETECTED DEADLOCK'} ) {
      @result{qw(deadlock_transactions deadlock_locks)}
         = $self->parse_deadlocks($innodb_sections{'LATEST DETECTED DEADLOCK'});
   }
   if ( $innodb_sections{'INSERT BUFFER AND ADAPTIVE HASH INDEX'} ) {
      $result{insert_buffer_pages} = [
         map {
            my %page;
            @page{qw(page buffer_count)}
               = $_ =~ m/Ibuf count for page $d is $d$/;
            \%page;
         } $innodb_sections{'INSERT BUFFER AND ADAPTIVE HASH INDEX'}
            =~ m/(^Ibuf count for page.*$)/gs
      ];
   }
   if ( $innodb_sections{'TRANSACTIONS'} ) {
      $result{transactions} = [
         map { $self->parse_txn($_) }
            $innodb_sections{'TRANSACTIONS'}
            =~ m/(---TRANSACTION \d.*?)(?=\n---TRANSACTION|$)/gs
      ];
      $result{transaction_locks} = [
         map {
            my $lock = {};
            $self->apply_rules($lock, $_, 'lock');
            $lock;
         }
         $innodb_sections{'TRANSACTIONS'} =~ m/(^(?:RECORD|TABLE) LOCKS?.*$)/gm
      ];
   }
   if ( $innodb_sections{'FILE I/O'} ) {
      $result{io_threads} = [
         map {
            my $thread = {};
            $self->apply_rules($thread, $_, 'io_thread');
            $thread;
         }
         $innodb_sections{'FILE I/O'} =~ m{^(I/O thread \d+ .*)$}gm
      ];
   }
   if ( $innodb_sections{SEMAPHORES} ) {
      $result{mutex_waits} = [
         map {
            my $cell = {};
            $self->apply_rules($cell, $_, 'mutex_wait');
            $cell;
         }
         $innodb_sections{SEMAPHORES} =~ m/^(--Thread.*?)^(?=Mutex spin|--Thread)/gms
      ];
   }

   return \%result;
}

sub apply_rules {
   my ($self, $hashref, $text, $rulename) = @_;
   my $rules = $parse_rules_for{$rulename}
      or die "There are no parse rules for '$rulename'";
   foreach my $rule ( @{$rules->{rules}} ) {
      @{$hashref}{ @{$rule->[$COLS]} } = $text =~ m/$rule->[$PATTERN]/m;
      # MKDEBUG && _d(@{$rule->[$COLS]}, $rule->[$PATTERN]);
      # MKDEBUG && _d(@{$hashref}{ @{$rule->[$COLS]} });
   }
   # Apply section-specific rules
   $rules->{customcode}->($hashref, $text);
}

sub parse_deadlocks {
   my ($self, $text) = @_;
   my (@txns, @locks);

   my @sections = $text
      =~ m{
         ^\*{3}\s([^\n]*)  # *** (1) WAITING FOR THIS...
         (.*?)             # Followed by anything, non-greedy
         (?=(?:^\*{3})|\z) # Followed by another three stars or EOF
      }gmsx;

   while ( my ($header, $body) = splice(@sections, 0, 2) ) {
      my ( $num, $what ) = $header =~ m/^\($d\) (.*):$/
         or next; # For the WE ROLL BACK case

      if ( $what eq 'TRANSACTION' ) {
         push @txns, $self->parse_txn($body);
      }
      else {
         my $lock = {};
         $self->apply_rules($lock, $body, 'lock');
         push @locks, $lock;
      }
   }

   my ( $rolled_back ) = $text =~ m/^\*\*\* WE ROLL BACK TRANSACTION \($d\)$/m;
   if ( $rolled_back ) {
      $txns[ $rolled_back - 1 ]->{victim} = 1;
   }

   return (\@txns, \@locks);
}

sub parse_txn {
   my ($self, $text) = @_;

   my $txn = {};
   $self->apply_rules($txn, $text, 'transaction');

   # Parsing the line that begins 'MySQL thread id' is complicated.  The only
   # thing always in the line is the thread and query id.  See function
   # innobase_mysql_print_thd() in InnoDB source file sql/ha_innodb.cc.
   my ( $thread_line ) = $text =~ m/^(MySQL thread id .*)$/m;
   my ( $mysql_thread_id, $query_id, $hostname, $ip, $user, $query_status );

   if ( $thread_line ) {
      # These parts can always be gotten.
      ( $mysql_thread_id, $query_id )
         = $thread_line =~ m/^MySQL thread id $d, query id $d/m;

      # If it's a master/slave thread, "Has (read|sent) all" may be the thread's
      # proc_info.  In these cases, there won't be any host/ip/user info
      ( $query_status ) = $thread_line =~ m/(Has (?:read|sent) all .*$)/m;
      if ( defined($query_status) ) {
         $user = 'system user';
      }

      # It may be the case that the query id is the last thing in the line.
      elsif ( $thread_line =~ m/query id \d+ / ) {
         # The IP address is the only non-word thing left, so it's the most
         # useful marker for where I have to start guessing.
         ( $hostname, $ip ) = $thread_line =~ m/query id \d+(?: ([A-Za-z]\S+))? $i/m;
         if ( defined $ip ) {
            ( $user, $query_status ) = $thread_line =~ m/$ip $w(?: (.*))?$/;
         }
         else { # OK, there wasn't an IP address.
            # There might not be ANYTHING except the query status.
            ( $query_status ) = $thread_line =~ m/query id \d+ (.*)$/;
            if ( $query_status !~ m/^\w+ing/ && !exists($is_proc_info{$query_status}) ) {
               # The remaining tokens are, in order: hostname, user, query_status.
               # It's basically impossible to know which is which.
               ( $hostname, $user, $query_status ) = $thread_line
                  =~ m/query id \d+(?: ([A-Za-z]\S+))?(?: $w(?: (.*))?)?$/m;
            }
            else {
               $user = 'system user';
            }
         }
      }
   }

   @{$txn}{qw(mysql_thread_id query_id hostname ip user query_status)}
      = ( $mysql_thread_id, $query_id, $hostname, $ip, $user, $query_status);

   return $txn;
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
# End InnoDBStatusParser package
# ###########################################################################
