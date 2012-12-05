#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use MySQLConfig;
use DSNParser;
use Sandbox;
use TextResultSetParser;
use PerconaTest;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $output;
my $sample = "t/lib/samples/configs/";
my $trp    = new TextResultSetParser();

throws_ok(
   sub {
      my $config = new MySQLConfig(
         TextResultSetParser => $trp,
      );
   },
   qr/I need a/,
   'Must specify an input'
);

throws_ok(
   sub {
      my $config = new MySQLConfig(
         file   => 'foo',
         output => 'bar',
         TextResultSetParser => $trp,
      );
   },
   qr/Specify only one/,
   'Must specify only one input'
);

throws_ok(
   sub {
      my $config = new MySQLConfig(
         file => 'fooz',
         TextResultSetParser => $trp,
      );
   },
   qr/Cannot open/,
   'Dies if file cannot be opened'
);

# #############################################################################
# parse_show_variables()
# #############################################################################
$output = load_file("t/lib/samples/show-variables/vars003.txt");
is_deeply(
   MySQLConfig::parse_show_variables(
      output              => $output,
      TextResultSetParser => $trp,
   ),
   {
      auto_increment_increment => '1',
      auto_increment_offset => '1',
      automatic_sp_privileges => 'ON',
      back_log => '50',
      basedir => '/home/daniel/mysql_binaries/mysql-5.0.82-linux-x86_64-glibc23/',
      binlog_cache_size => '32768',
      bulk_insert_buffer_size => '8388608',
      character_set_client => 'latin1',
      character_set_connection => 'latin1',
      character_set_database => 'latin1',
      character_set_filesystem => 'binary',
      character_set_results => 'latin1',
      character_set_server => 'latin1',
      character_set_system => 'utf8',
      character_sets_dir => '/home/daniel/mysql_binaries/mysql-5.0.82-linux-x86_64-glibc23/share/mysql/charsets/',
      collation_connection => 'latin1_swedish_ci',
      collation_database => 'latin1_swedish_ci',
      collation_server => 'latin1_swedish_ci',
      completion_type => '0',
      concurrent_insert => '1',
      connect_timeout => '10',
      datadir => '/tmp/12345/data/',
      date_format => '%Y-%m-%d',
      datetime_format => '%Y-%m-%d %H:%i:%s',
      default_week_format => '0',
      delay_key_write => 'ON',
      delayed_insert_limit => '100',
      delayed_insert_timeout => '300',
      delayed_queue_size => '1000',
      div_precision_increment => '4',
      engine_condition_pushdown => 'OFF',
      expire_logs_days => '0',
      flush => 'OFF',
      flush_time => '0',
      ft_boolean_syntax => '',
      ft_max_word_len => '84',
      ft_min_word_len => '4',
      ft_query_expansion_limit => '20',
      ft_stopword_file => '(built-in)',
      group_concat_max_len => '1024',
      have_archive => 'YES',
      have_bdb => 'NO',
      have_blackhole_engine => 'YES',
      have_community_features => 'YES',
      have_compress => 'YES',
      have_crypt => 'YES',
      have_csv => 'YES',
      have_dynamic_loading => 'YES',
      have_example_engine => 'NO',
      have_federated_engine => 'YES',
      have_geometry => 'YES',
      have_innodb => 'YES',
      have_isam => 'NO',
      have_merge_engine => 'YES',
      have_ndbcluster => 'DISABLED',
      have_openssl => 'DISABLED',
      have_profiling => 'YES',
      have_query_cache => 'YES',
      have_raid => 'NO',
      have_rtree_keys => 'YES',
      have_ssl => 'DISABLED',
      have_symlink => 'YES',
      hostname => 'dante',
      init_connect => '',
      init_file => '',
      init_slave => '',
      innodb_adaptive_hash_index => 'ON',
      innodb_additional_mem_pool_size => '1048576',
      innodb_autoextend_increment => '8',
      innodb_buffer_pool_awe_mem_mb => '0',
      innodb_buffer_pool_size => '16777216',
      innodb_checksums => 'ON',
      innodb_commit_concurrency => '0',
      innodb_concurrency_tickets => '500',
      innodb_data_file_path => 'ibdata1:10M:autoextend',
      innodb_data_home_dir => '/tmp/12345/data',
      innodb_doublewrite => 'ON',
      innodb_fast_shutdown => '1',
      innodb_file_io_threads => '4',
      innodb_file_per_table => 'OFF',
      innodb_flush_log_at_trx_commit => '1',
      innodb_flush_method => '',
      innodb_force_recovery => '0',
      innodb_lock_wait_timeout => '50',
      innodb_locks_unsafe_for_binlog => 'OFF',
      innodb_log_arch_dir => '',
      innodb_log_archive => 'OFF',
      innodb_log_buffer_size => '1048576',
      innodb_log_file_size => '5242880',
      innodb_log_files_in_group => '2',
      innodb_log_group_home_dir => '/tmp/12345/data',
      innodb_max_dirty_pages_pct => '90',
      innodb_max_purge_lag => '0',
      innodb_mirrored_log_groups => '1',
      innodb_open_files => '300',
      innodb_rollback_on_timeout => 'OFF',
      innodb_support_xa => 'ON',
      innodb_sync_spin_loops => '20',
      innodb_table_locks => 'ON',
      innodb_thread_concurrency => '8',
      innodb_thread_sleep_delay => '10000',
      innodb_use_legacy_cardinality_algorithm => 'ON',
      interactive_timeout => '28800',
      join_buffer_size => '131072',
      keep_files_on_create => 'OFF',
      key_buffer_size => '16777216',
      key_cache_age_threshold => '300',
      key_cache_block_size => '1024',
      key_cache_division_limit => '100',
      language => '/home/daniel/mysql_binaries/mysql-5.0.82-linux-x86_64-glibc23/share/mysql/english/',
      large_files_support => 'ON',
      large_page_size => '0',
      large_pages => 'OFF',
      lc_time_names => 'en_US',
      license => 'GPL',
      local_infile => 'ON',
      locked_in_memory => 'OFF',
      log => 'OFF',
      log_bin => 'ON',
      log_bin_trust_function_creators => 'OFF',
      log_error => '',
      log_queries_not_using_indexes => 'OFF',
      log_slave_updates => 'ON',
      log_slow_queries => 'OFF',
      log_warnings => '1',
      long_query_time => '10',
      low_priority_updates => 'OFF',
      lower_case_file_system => 'OFF',
      lower_case_table_names => '0',
      max_allowed_packet => '1048576',
      max_binlog_cache_size => '18446744073709547520',
      max_binlog_size => '1073741824',
      max_connect_errors => '10',
      max_connections => '100',
      max_delayed_threads => '20',
      max_error_count => '64',
      max_heap_table_size => '16777216',
      max_insert_delayed_threads => '20',
      max_join_size => '18446744073709551615',
      max_length_for_sort_data => '1024',
      max_prepared_stmt_count => '16382',
      max_relay_log_size => '0',
      max_seeks_for_key => '18446744073709551615',
      max_sort_length => '1024',
      max_sp_recursion_depth => '0',
      max_tmp_tables => '32',
      max_user_connections => '0',
      max_write_lock_count => '18446744073709551615',
      multi_range_count => '256',
      myisam_data_pointer_size => '6',
      myisam_max_sort_file_size => '9223372036853727232',
      myisam_recover_options => 'OFF',
      myisam_repair_threads => '1',
      myisam_sort_buffer_size => '8388608',
      myisam_stats_method => 'nulls_unequal',
      ndb_autoincrement_prefetch_sz => '1',
      ndb_cache_check_time => '0',
      ndb_connectstring => '',
      ndb_force_send => 'ON',
      ndb_use_exact_count => 'ON',
      ndb_use_transactions => 'ON',
      net_buffer_length => '16384',
      net_read_timeout => '30',
      net_retry_count => '10',
      net_write_timeout => '60',
      new => 'OFF',
      old_passwords => 'OFF',
      open_files_limit => '1024',
      optimizer_prune_level => '1',
      optimizer_search_depth => '62',
      pid_file => '/tmp/12345/data/mysql_sandbox12345.pid',
      plugin_dir => '',
      port => '12345',
      preload_buffer_size => '32768',
      profiling => 'OFF',
      profiling_history_size => '15',
      protocol_version => '10',
      query_alloc_block_size => '8192',
      query_cache_limit => '1048576',
      query_cache_min_res_unit => '4096',
      query_cache_size => '0',
      query_cache_type => 'ON',
      query_cache_wlock_invalidate => 'OFF',
      query_prealloc_size => '8192',
      range_alloc_block_size => '4096',
      read_buffer_size => '131072',
      read_only => 'OFF',
      read_rnd_buffer_size => '262144',
      relay_log => 'mysql-relay-bin',
      relay_log_index => '',
      relay_log_info_file => 'relay-log.info',
      relay_log_purge => 'ON',
      relay_log_space_limit => '0',
      rpl_recovery_rank => '0',
      secure_auth => 'OFF',
      secure_file_priv => '',
      server_id => '12345',
      skip_external_locking => 'ON',
      skip_networking => 'OFF',
      skip_show_database => 'OFF',
      slave_compressed_protocol => 'OFF',
      slave_load_tmpdir => '/tmp/',
      slave_net_timeout => '3600',
      slave_skip_errors => 'OFF',
      slave_transaction_retries => '10',
      slow_launch_time => '2',
      socket => '/tmp/12345/mysql_sandbox12345.sock',
      sort_buffer_size => '2097144',
      sql_big_selects => 'ON',
      sql_mode => '',
      sql_notes => 'ON',
      sql_warnings => 'OFF',
      ssl_ca => '',
      ssl_capath => '',
      ssl_cert => '',
      ssl_cipher => '',
      ssl_key => '',
      storage_engine => 'MyISAM',
      sync_binlog => '0',
      sync_frm => 'ON',
      system_time_zone => 'MDT',
      table_cache => '64',
      table_lock_wait_timeout => '50',
      table_type => 'MyISAM',
      thread_cache_size => '0',
      thread_stack => '262144',
      time_format => '%H:%i:%s',
      time_zone => 'SYSTEM',
      timed_mutexes => 'OFF',
      tmp_table_size => '33554432',
      tmpdir => '/tmp/',
      transaction_alloc_block_size => '8192',
      transaction_prealloc_size => '4096',
      tx_isolation => 'REPEATABLE-READ',
      updatable_views_with_limit => 'YES',
      version => '5.0.82-log',
      version_comment => 'MySQL Community Server (GPL)',
      version_compile_machine => 'x86_64',
      version_compile_os => 'unknown-linux-gnu',
      wait_timeout => '28800'
   },
   'parse_show_variables()',
);

# #############################################################################
# Config from mysqld --help --verbose
# #############################################################################
my $config = new MySQLConfig(
   file                => "$trunk/$sample/mysqldhelp001.txt",
   TextResultSetParser => $trp,
);

is(
   $config->format(),
   'mysqld',
   "Detect mysqld type"
);

is_deeply(
   $config->variables(),
   {
      abort_slave_event_count => '0',
      allow_suspicious_udfs => 'FALSE',
      auto_increment_increment => '1',
      auto_increment_offset => '1',
      automatic_sp_privileges => 'TRUE',
      back_log => '50',
      basedir => '/home/daniel/mysql_binaries/mysql-5.0.82-linux-x86_64-glibc23',
      bdb => 'FALSE',
      bind_address => '',
      binlog_cache_size => '32768',
      bulk_insert_buffer_size => '8388608',
      character_set_client_handshake => 'TRUE',
      character_set_filesystem => 'binary',
      character_set_server => 'latin1',
      character_sets_dir => '/home/daniel/mysql_binaries/mysql-5.0.82-linux-x86_64-glibc23/share/mysql/charsets/',
      chroot => '',
      collation_server => 'latin1_swedish_ci',
      completion_type => '0',
      concurrent_insert => '1',
      connect_timeout => '10',
      console => 'FALSE',
      datadir => '/tmp/12345/data/',
      date_format => '',
      datetime_format => '',
      default_character_set => 'latin1',
      default_collation => 'latin1_swedish_ci',
      default_time_zone => '',
      default_week_format => '0',
      delayed_insert_limit => '100',
      delayed_insert_timeout => '300',
      delayed_queue_size => '1000',
      des_key_file => '',
      disconnect_slave_event_count => '0',
      div_precision_increment => '4',
      enable_locking => 'FALSE',
      enable_pstack => 'FALSE',
      engine_condition_pushdown => 'FALSE',
      expire_logs_days => '0',
      external_locking => 'FALSE',
      federated => 'TRUE',
      flush_time => '0',
      ft_max_word_len => '84',
      ft_min_word_len => '4',
      ft_query_expansion_limit => '20',
      ft_stopword_file => '',
      gdb => 'FALSE',
      group_concat_max_len => '1024',
      help => 'TRUE',
      init_connect => '',
      init_file => '',
      init_slave => '',
      innodb => 'TRUE',
      innodb_adaptive_hash_index => 'TRUE',
      innodb_additional_mem_pool_size => '1048576',
      innodb_autoextend_increment => '8',
      innodb_buffer_pool_awe_mem_mb => '0',
      innodb_buffer_pool_size => '16777216',
      innodb_checksums => 'TRUE',
      innodb_commit_concurrency => '0',
      innodb_concurrency_tickets => '500',
      innodb_data_home_dir => '/tmp/12345/data',
      innodb_doublewrite => 'TRUE',
      innodb_fast_shutdown => '1',
      innodb_file_io_threads => '4',
      innodb_file_per_table => 'FALSE',
      innodb_flush_log_at_trx_commit => '1',
      innodb_flush_method => '',
      innodb_force_recovery => '0',
      innodb_lock_wait_timeout => '3',
      innodb_locks_unsafe_for_binlog => 'FALSE',
      innodb_log_arch_dir => '',
      innodb_log_buffer_size => '1048576',
      innodb_log_file_size => '5242880',
      innodb_log_files_in_group => '2',
      innodb_log_group_home_dir => '/tmp/12345/data',
      innodb_max_dirty_pages_pct => '90',
      innodb_max_purge_lag => '0',
      innodb_mirrored_log_groups => '1',
      innodb_open_files => '300',
      innodb_rollback_on_timeout => 'FALSE',
      innodb_status_file => 'FALSE',
      innodb_support_xa => 'TRUE',
      innodb_sync_spin_loops => '20',
      innodb_table_locks => 'TRUE',
      innodb_thread_concurrency => '8',
      innodb_thread_sleep_delay => '10000',
      innodb_use_legacy_cardinality_algorithm => 'TRUE',
      interactive_timeout => '28800',
      isam => 'FALSE',
      join_buffer_size => '131072',
      keep_files_on_create => 'FALSE',
      key_buffer_size => '16777216',
      key_cache_age_threshold => '300',
      key_cache_block_size => '1024',
      key_cache_division_limit => '100',
      language => '/home/daniel/mysql_binaries/mysql-5.0.82-linux-x86_64-glibc23/share/mysql/english/',
      large_pages => 'FALSE',
      lc_time_names => 'en_US',
      local_infile => 'TRUE',
      log => 'OFF',
      log_bin => 'mysql-bin',
      log_bin_index => 'OFF',
      log_bin_trust_function_creators => 'FALSE',
      log_bin_trust_routine_creators => 'FALSE',
      log_error => '',
      log_isam => 'myisam.log',
      log_queries_not_using_indexes => 'FALSE',
      log_short_format => 'FALSE',
      log_slave_updates => 'TRUE',
      log_slow_admin_statements => 'FALSE',
      log_slow_queries => 'OFF',
      log_tc => 'tc.log',
      log_tc_size => '24576',
      log_update => 'OFF',
      log_warnings => '1',
      long_query_time => '10',
      low_priority_updates => 'FALSE',
      lower_case_table_names => '0',
      master_connect_retry => '60',
      master_host => '',
      master_info_file => 'master.info',
      master_password => '',
      master_port => '3306',
      master_retry_count => '86400',
      master_ssl => 'FALSE',
      master_ssl_ca => '',
      master_ssl_capath => '',
      master_ssl_cert => '',
      master_ssl_cipher => '',
      master_ssl_key => '',
      master_user => 'test',
      max_allowed_packet => '1048576',
      max_binlog_cache_size => '18446744073709547520',
      max_binlog_dump_events => '0',
      max_binlog_size => '1073741824',
      max_connect_errors => '10',
      max_connections => '100',
      max_delayed_threads => '20',
      max_error_count => '64',
      max_heap_table_size => '16777216',
      max_join_size => '18446744073709551615',
      max_length_for_sort_data => '1024',
      max_prepared_stmt_count => '16382',
      max_relay_log_size => '0',
      max_seeks_for_key => '18446744073709551615',
      max_sort_length => '1024',
      max_sp_recursion_depth => '0',
      max_tmp_tables => '32',
      max_user_connections => '0',
      max_write_lock_count => '18446744073709551615',
      memlock => 'FALSE',
      merge => 'TRUE',
      multi_range_count => '256',
      myisam_block_size => '1024',
      myisam_data_pointer_size => '6',
      myisam_max_extra_sort_file_size => '2147483648',
      myisam_max_sort_file_size => '9223372036853727232',
      myisam_recover => 'OFF',
      myisam_repair_threads => '1',
      myisam_sort_buffer_size => '8388608',
      myisam_stats_method => 'nulls_unequal',
      ndb_autoincrement_prefetch_sz => '1',
      ndb_cache_check_time => '0',
      ndb_connectstring => '',
      ndb_force_send => 'TRUE',
      ndb_mgmd_host => '',
      ndb_nodeid => '0',
      ndb_optimized_node_selection => 'TRUE',
      ndb_shm => 'FALSE',
      ndb_use_exact_count => 'TRUE',
      ndb_use_transactions => 'TRUE',
      ndbcluster => 'FALSE',
      net_buffer_length => '16384',
      net_read_timeout => '30',
      net_retry_count => '10',
      net_write_timeout => '60',
      new => 'FALSE',
      old_passwords => 'FALSE',
      old_style_user_limits => 'FALSE',
      open_files_limit => '0',
      optimizer_prune_level => '1',
      optimizer_search_depth => '62',
      pid_file => '/tmp/12345/data/mysql_sandbox12345.pid',
      plugin_dir => '',
      port => '12345',
      port_open_timeout => '0',
      preload_buffer_size => '32768',
      profiling_history_size => '15',
      query_alloc_block_size => '8192',
      query_cache_limit => '1048576',
      query_cache_min_res_unit => '4096',
      query_cache_size => '0',
      query_cache_type => '1',
      query_cache_wlock_invalidate => 'FALSE',
      query_prealloc_size => '8192',
      range_alloc_block_size => '4096',
      read_buffer_size => '131072',
      read_only => 'FALSE',
      read_rnd_buffer_size => '262144',
      record_buffer => '131072',
      relay_log => 'mysql-relay-bin',
      relay_log_index => '',
      relay_log_info_file => 'relay-log.info',
      relay_log_purge => 'TRUE',
      relay_log_space_limit => '0',
      replicate_same_server_id => 'FALSE',
      report_host => '127.0.0.1',
      report_password => '',
      report_port => '12345',
      report_user => '',
      rpl_recovery_rank => '0',
      safe_user_create => 'FALSE',
      secure_auth => 'FALSE',
      secure_file_priv => '',
      server_id => '12345',
      show_slave_auth_info => 'FALSE',
      skip_grant_tables => 'FALSE',
      skip_slave_start => 'FALSE',
      slave_compressed_protocol => 'FALSE',
      slave_load_tmpdir => '/tmp/',
      slave_net_timeout => '3600',
      slave_transaction_retries => '10',
      slow_launch_time => '2',
      socket => '/tmp/12345/mysql_sandbox12345.sock',
      sort_buffer_size => '2097144',
      sporadic_binlog_dump_fail => 'FALSE',
      sql_mode => 'OFF',
      ssl => 'FALSE',
      ssl_ca => '',
      ssl_capath => '',
      ssl_cert => '',
      ssl_cipher => '',
      ssl_key => '',
      symbolic_links => 'TRUE',
      sync_binlog => '0',
      sync_frm => 'TRUE',
      sysdate_is_now => 'FALSE',
      table_cache => '64',
      table_lock_wait_timeout => '50',
      tc_heuristic_recover => '',
      temp_pool => 'TRUE',
      thread_cache_size => '0',
      thread_concurrency => '10',
      thread_stack => '262144',
      time_format => '',
      timed_mutexes => 'FALSE',
      tmp_table_size => '33554432',
      tmpdir => '',
      transaction_alloc_block_size => '8192',
      transaction_prealloc_size => '4096',
      updatable_views_with_limit => '1',
      use_symbolic_links => 'TRUE',
      verbose => 'TRUE',
      wait_timeout => '28800',
      warnings => '1'
   },
   'mysqldhelp001.txt'
);

is(
   $config->value_of('wait_timeout'),
   28800,
   'value_of() from mysqld'
);

ok(
   $config->has('wait_timeout'),
   'has() from mysqld'
);

ok(
  !$config->has('foo'),
  "has(), doesn't have it"
);

# #############################################################################
# Config from SHOW VARIABLES
# #############################################################################
$config = new MySQLConfig(
   result_set          => [ [qw(foo bar)], [qw(a z)] ],
   TextResultSetParser => $trp,
);

is(
   $config->format(),
   'show_variables',
   "Detect show_variables type (arrayref)"
);

is_deeply(
   $config->variables(),
   {
      foo => 'bar',
      a   => 'z',
   },
   'Variables from arrayref'
);

is(
   $config->value_of('foo'),
   'bar',
   'value_of() from arrayref',
);

ok(
   $config->has('foo'),
   'has() from arrayref',
);

# #############################################################################
# Config from my_print_defaults
# #############################################################################
$config = new MySQLConfig(
   file                => "$trunk/$sample/myprintdef001.txt",
   TextResultSetParser => $trp,
);

is(
   $config->format(),
   'my_print_defaults',
   "Detect my_print_defaults type"
);

is(
   $config->value_of('port'),
   '12349',
   "Duplicate var's last value used"
);

is(
   $config->value_of('innodb_buffer_pool_size'),
   '16777216',
   'Converted size char to int'
);

is(
   $config->value_of('log_slave_updates'),
   'ON',
   "Var is ON if specified in my_print_defaults"
);

is_deeply(
   $config->duplicate_variables(),
   {
      'port' => [12345],
   },
   'duplicate_variables()'
);

# #############################################################################
# Config from option file (my.cnf)
# #############################################################################
$config = new MySQLConfig(
   file                => "$trunk/$sample/mycnf001.txt",
   TextResultSetParser => $trp,
);

is(
   $config->format(),
   'option_file',
   "Detect option_file type"
);

is_deeply(
   $config->variables(),
   {
      'user'                  => 'mysql',
      'pid_file'              => '/var/run/mysqld/mysqld.pid',
      'socket'                => '/var/run/mysqld/mysqld.sock',
      'port'                  => 3306,
      'basedir'               => '/usr',
      'datadir'               => '/var/lib/mysql',
      'tmpdir'		            => '/tmp',
      'skip_external_locking' => 'ON',
      'bind_address'		      => '127.0.0.1',
      'key_buffer'		      => 16777216,
      'max_allowed_packet'	   => 16777216,
      'thread_stack'		      => 131072,
      'thread_cache_size'	   => 8,
      'myisam_recover'		   => 'BACKUP',
      'query_cache_limit'     => 1048576,
      'query_cache_size'      => 16777216,
      'expire_logs_days'	   => 10,
      'max_binlog_size'       => 104857600,
      'skip_federated'        => 'ON',
   },
   "Vars from option file"
) or print Dumper($config->variables());

$config = new MySQLConfig(
   file                => "$trunk/$sample/mycnf002.txt",
   TextResultSetParser => $trp,
);

is_deeply(
   $config->variables(),
   {
      var1  => '16777216',    # 16 Mb
      var2  => '16777216',
      var3  => '16777216',
      var4  => '16777216',
      var5  => '16384',       # 16 Kb
      var6  => '16384',
      var7  => '16384',
      var8  => '16384',
      var9  => '1073741824',  # 1 Gb
      var10 => '1073741824',
      var11 => '1073741824',
      var12 => '1073741824',
   },
   "Size postfixes MB, KB, etc."
) or print Dumper($config->variables());

# ############################################################################
# Baron's test cases.
# ############################################################################
$config = new MySQLConfig(
   file                => "$trunk/$sample/mycnf-baron-001.txt",
   TextResultSetParser => $trp,
);

is_deeply(
   $config->variables(),
   {
      'datadir'      => '/home/baron/etc/mysql/server/5.1.50/data/',
      'port'         => '5150',
      'socket'       => '/home/baron/etc/mysql/server/5.1.50/data/mysql.sock',
      'language'     => './share/english',
      'basedir'      => '/home/baron/etc/mysql/server/5.1.50',
      'log_bin'      => 'ON',
      'plugin_load'  => 'innodb=ha_innodb_plugin.so.0;innodb_trx=ha_innodb_plugin.so.0;innodb_locks=ha_innodb_plugin.so.0;innodb_cmp=ha_innodb_plugin.so.0;innodb_cmp_reset=ha_innodb_plugin.so.0;innodb_cmpmem=ha_innodb_plugin.so.0;innodb_cmpmem_reset=ha_innodb_plugin.so.0',
      'ignore_builtin_innodb' => 'ON',
   },
   "mycnf-baron-001.cnf"
);

$config = new MySQLConfig(
   file => "$trunk/t/lib/samples/show-variables/vars-baron-001.txt",
   TextResultSetParser => $trp,
);

is(
   $config->format(),
   'show_variables',
   'Detect show_variables type for unformatted SHOW VARIABLES output'
);

is(
   $config->value_of('wait_timeout'),
   28800,
   "Get vars from unformatted SHOW VARIABLES output"
);

$config = new MySQLConfig(
   file                => "$trunk/$sample/mycnf-baron-002.txt",
   TextResultSetParser => $trp,
);

is_deeply(
   $config->value_of('innodb_file_per_table'),
   'ON',
   "innodb_file_per_table (mycnf-baron-002.cnf)"
);

# #############################################################################
# Online test.
# #############################################################################
SKIP: {
   skip 'Cannot connect to sandbox master', 3 unless $dbh;

   $config = new MySQLConfig(
      dbh => $dbh,
   );

   is(
      $config->format(),
      "show_variables",
      "Detect show_variables type (dbh)"
   );

   is(
      $config->value_of('datadir'),
      '/tmp/12345/data/',
      "Vars from dbh"
   );

   like(
      $config->mysql_version(),
      qr/5\.\d+\.\d+/,
      "MySQL version from dbh"
   );
}

$config = new MySQLConfig(
   file => "$trunk/t/lib/samples/configs/mycnf-kc-001.txt",
   TextResultSetParser => $trp,
);
is(
  $config->value_of('user'),
  'mysql',
  'end of line comment in option file'
);

is(
  $config->value_of('password'),
  'password # still part of it!',
  'end of line comments respect quoted values'
);

is(
  $config->value_of('something'),
  'something ; or # another',
  "..and removing comments doesn't leave trailing whitespace"
);

ok(
   defined $config->value_of('log_bin'),
   "bools with comments in the end are found"
);

is(
   $config->value_of('log_bin'),
   "ON",
   "And the comment is correctly stripped out"
);

is_deeply(
   [ sort keys %{$config->variables} ],
   [ sort qw( password something user log_bin )],
   "start of line comments with # or ; are ignored"
);

# #############################################################################
# Use of uninitialized value in substitution (s///) at pt-config-diff line 1996
# https://bugs.launchpad.net/percona-toolkit/+bug/917770
# #############################################################################

$config = eval {
   new MySQLConfig(
      file                => "$trunk/t/pt-config-diff/samples/bug_917770.cnf",
      TextResultSetParser => $trp,
   );
};

is(
   $EVAL_ERROR,
   '',
   "Bug 917770: Lives ok on lines with just spaces"
);

is(
   $config->format(),
   'option_file',
   "Detect option_file type"
);

# #############################################################################
# Done.
# #############################################################################
{
   local *STDERR;
   open STDERR, '>', \$output;
   $config->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;
exit;
