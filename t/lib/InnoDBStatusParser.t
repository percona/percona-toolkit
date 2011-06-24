#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 2;

use InnoDBStatusParser;
use MaatkitTest;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $is = new InnoDBStatusParser();
isa_ok($is, 'InnoDBStatusParser');

# Very basic status on quiet sandbox server.
is_deeply(
   $is->parse(load_file('t/lib/samples/is001.txt')),
      {
        deadlock_locks => [],
        deadlock_transactions => [],
        insert_buffer_pages => [],
        io_threads => [
          {
            event_set => undef,
            id => '0',
            io_avg_wait => undef,
            io_reads => undef,
            io_requests => undef,
            io_wait => undef,
            io_writes => undef,
            max_io_wait => undef,
            purpose => 'insert buffer thread',
            state => 'waiting for i/o request'
          },
          {
            event_set => undef,
            id => '1',
            io_avg_wait => undef,
            io_reads => undef,
            io_requests => undef,
            io_wait => undef,
            io_writes => undef,
            max_io_wait => undef,
            purpose => 'log thread',
            state => 'waiting for i/o request'
          },
          {
            event_set => undef,
            id => '2',
            io_avg_wait => undef,
            io_reads => undef,
            io_requests => undef,
            io_wait => undef,
            io_writes => undef,
            max_io_wait => undef,
            purpose => 'read thread',
            state => 'waiting for i/o request'
          },
          {
            event_set => undef,
            id => '3',
            io_avg_wait => undef,
            io_reads => undef,
            io_requests => undef,
            io_wait => undef,
            io_writes => undef,
            max_io_wait => undef,
            purpose => 'write thread',
            state => 'waiting for i/o request'
          }
        ],
        mutex_waits => [],
        status => [
          {
            Innodb_awe_memory_allocated => undef,
            Innodb_buffer_pool_awe_mapped => undef,
            Innodb_buffer_pool_awe_memory_frames => undef,
            Innodb_buffer_pool_awe_pages_remapped_sec => undef,
            Innodb_buffer_pool_hit_rate => '1',
            Innodb_buffer_pool_pages_created => '178',
            Innodb_buffer_pool_pages_created_sec => '0.00',
            Innodb_buffer_pool_pages_data => '178',
            Innodb_buffer_pool_pages_dirty => '0',
            Innodb_buffer_pool_pages_free => '333',
            Innodb_buffer_pool_pages_read => '0',
            Innodb_buffer_pool_pages_read_sec => '0.00',
            Innodb_buffer_pool_pages_total => '512',
            Innodb_buffer_pool_pages_written => '189',
            Innodb_buffer_pool_pages_written_sec => '0.43',
            Innodb_buffer_pool_pending_data_writes => '0',
            Innodb_buffer_pool_pending_dirty_writes => '0',
            Innodb_buffer_pool_pending_fsyncs => 0,
            Innodb_buffer_pool_pending_reads => '0',
            Innodb_buffer_pool_pending_single_writes => '0',
            Innodb_common_memory_allocated => '675584',
            Innodb_data_bytes_per_read => '0',
            Innodb_data_fsyncs => '16',
            Innodb_data_fsyncs_sec => '0.08',
            Innodb_data_pending_fsyncs => 0,
            Innodb_data_pending_preads => undef,
            Innodb_data_pending_pwrites => undef,
            Innodb_data_reads => '0',
            Innodb_data_reads_sec => '0.00',
            Innodb_data_writes => '38',
            Innodb_data_writes_sec => '0.14',
            Innodb_dictionary_memory_allocated => undef,
            Innodb_hash_searches_sec => '0.00',
            Innodb_hash_table_buf_frames_reserved => '1',
            Innodb_hash_table_size => '17393',
            Innodb_hash_table_used_cells => '0',
            Innodb_history_list_length => '0',
            Innodb_insert_buffer_free_list_length => '0',
            Innodb_insert_buffer_inserts => '0',
            Innodb_insert_buffer_merged_records => '0',
            Innodb_insert_buffer_merges => '0',
            Innodb_insert_buffer_pending_reads => '0',
            Innodb_insert_buffer_segment_size => '2',
            Innodb_insert_buffer_size => '1',
            Innodb_lock_struct_count => '0',
            Innodb_lock_wait_timeouts => undef,
            Innodb_log_caller_write_background_async => undef,
            Innodb_log_caller_write_background_sync => undef,
            Innodb_log_caller_write_buffer_pool => undef,
            Innodb_log_caller_write_checkpoint_async => undef,
            Innodb_log_caller_write_checkpoint_sync => undef,
            Innodb_log_caller_write_commit_async => undef,
            Innodb_log_caller_write_commit_sync => undef,
            Innodb_log_caller_write_internal => undef,
            Innodb_log_caller_write_log_archive => undef,
            Innodb_log_flushed_to => '0 43655',
            Innodb_log_ios => '11',
            Innodb_log_ios_sec => '0.03',
            Innodb_log_last_checkpoint => '0 43655',
            Innodb_log_pending_chkp_writes => '0',
            Innodb_log_pending_io => '0',
            Innodb_log_pending_writes => '0',
            Innodb_log_sequence_no => '0 43655',
            Innodb_log_syncer_write_background_async => undef,
            Innodb_log_syncer_write_background_sync => undef,
            Innodb_log_syncer_write_buffer_pool => undef,
            Innodb_log_syncer_write_checkpoint_async => undef,
            Innodb_log_syncer_write_checkpoint_sync => undef,
            Innodb_log_syncer_write_commit_async => undef,
            Innodb_log_syncer_write_commit_sync => undef,
            Innodb_log_syncer_write_internal => undef,
            Innodb_log_syncer_write_log_archive => undef,
            Innodb_main_thread_id => '140284306659664',
            Innodb_main_thread_proc_no => '4257',
            Innodb_main_thread_state => 'waiting for server activity',
            Innodb_mutex_os_waits => '0',
            Innodb_mutex_rw_excl_os_waits => '0',
            Innodb_mutex_rw_excl_spins => '0',
            Innodb_mutex_rw_shared_os_waits => '7',
            Innodb_mutex_rw_shared_spins => '14',
            Innodb_mutex_spin_rounds => '2',
            Innodb_mutex_spin_waits => '0',
            Innodb_nonhash_searches_sec => '0.00',
            Innodb_num_io_threads => 4,
            Innodb_os_log_pending_fsyncs => 0,
            Innodb_pending_aio_reads => '0',
            Innodb_pending_aio_writes => '0',
            Innodb_pending_sync_io => '0',
            Innodb_purged_to => '0 0',
            Innodb_read_views_open => '1',
            Innodb_reserved_extent_count => undef,
            Innodb_rows_deleted => '0',
            Innodb_rows_deleted_sec => '0.00',
            Innodb_rows_inserted => '0',
            Innodb_rows_inserted_sec => '0.00',
            Innodb_rows_read => '0',
            Innodb_rows_read_sec => '0.00',
            Innodb_rows_updated => '0',
            Innodb_rows_updated_sec => '0.00',
            Innodb_status_interval => '37',
            Innodb_status_time => '2009-07-07 13:18:38',
            Innodb_status_truncated => 0,
            Innodb_threads_inside_kernel => '0',
            Innodb_threads_queued => '0',
            Innodb_total_memory_allocated => '20634452',
            Innodb_transaction_counter => '0 769',
            Innodb_transactions => 1,
            Innodb_transactions_truncated => 0,
            Innodb_undo_log_record => '0 0',
            Innodb_wait_array_reservation_count => '7',
            Innodb_wait_array_signal_count => '7'
          }
        ],
        transaction_locks => [],
        transactions => [
          {
            active_secs => undef,
            heap_size => undef,
            hostname => 'localhost',
            ip => undef,
            lock_structs => undef,
            lock_wait_time => undef,
            mysql_tables_locked => undef,
            mysql_tables_used => undef,
            mysql_thread_id => '3',
            os_thread_id => '140284242860368',
            proc_no => '4257',
            query_id => '11',
            query_status => undef,
            query_text => 'show innodb status',
            read_view_lower_limit => undef,
            read_view_upper_limit => undef,
            row_locks => undef,
            thread_status => undef,
            tickets => undef,
            txn_id => '0 0',
            txn_query_status => undef,
            txn_status => 'not started',
            undo_log_entries => undef,
            user => 'msandbox'
          }
        ]
      },
   'Basic InnoDB status'
);

# #############################################################################
# Done.
# #############################################################################
exit;
