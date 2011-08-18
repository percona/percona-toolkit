#!/usr/bin/env bash

# This test file must be ran by util/test-bash-functions.

TESTS=6

# ############################################################################
TEST_NAME="stacktrace-001.txt"
# ############################################################################
cat > $TMPDIR/expected <<EOF
    187 __lll_mutex_lock_wait,_L_mutex_lock_1133,pthread_mutex_lock,safe_mutex_lock,open_table,open_tables,open_and_lock_tables,mysql_execute_command,mysql_parse,dispatch_command,handle_one_connection,start_thread,clone
     62 __lll_mutex_lock_wait,_L_mutex_lock_1133,pthread_mutex_lock,safe_mutex_lock,close_thread_tables,dispatch_command,handle_one_connection,start_thread,clone
     39 read,vio_read,my_real_read,my_net_read,handle_one_connection,start_thread,clone
     18 pthread_cond_wait,safe_cond_wait,os_event_wait_low,os_aio_simulated_handle,fil_aio_wait,io_handler_thread,start_thread,clone
     15 pthread_cond_wait,safe_cond_wait,end_thread,handle_one_connection,start_thread,clone
     15 __lll_mutex_lock_wait,_L_mutex_lock_1133,pthread_mutex_lock,safe_mutex_lock,open_table,open_tables,mysql_update,mysql_execute_command,mysql_parse,dispatch_command,handle_one_connection,start_thread,clone
     12 __lll_mutex_lock_wait,_L_mutex_lock_1133,pthread_mutex_lock,safe_mutex_lock,open_table,open_tables,open_and_lock_tables,mysql_insert,mysql_execute_command,mysql_parse,dispatch_command,handle_one_connection,start_thread,clone
      2 __lll_mutex_lock_wait,_L_mutex_lock_107,pthread_mutex_lock,safe_mutex_lock,Log_event::read_log_event,mysql_binlog_send,dispatch_command,handle_one_connection,start_thread,clone
      1 select,os_thread_sleep,srv_master_thread,start_thread,clone
      1 select,os_thread_sleep,srv_lock_timeout_and_monitor_thread,start_thread,clone
      1 select,os_thread_sleep,srv_error_monitor_thread,start_thread,clone
      1 select,handle_connections_sockets,main
      1 _sanity,_myfree,st_join_table::cleanup,JOIN::cleanup,JOIN::join_free,do_select,JOIN::exec,mysql_select,handle_select,mysql_execute_command,mysql_parse,dispatch_command,handle_one_connection,start_thread,clone
      1 pread64,_os_file_pread,_os_file_read,_fil_io,buf_read_page_low,buf_read_page,buf_page_get_gen,btr_cur_search_to_nth_level,btr_estimate_n_rows_in_range,ha_innobase::records_in_range,check_quick_keys,check_quick_select,get_key_scans_params,SQL_SELECT::test_quick_select,mysql_update,mysql_execute_command,mysql_parse,dispatch_command,handle_one_connection,start_thread,clone
      1 __lll_mutex_lock_wait,_L_mutex_lock_1133,pthread_mutex_lock,safe_mutex_lock,_sanity,_myrealloc,String::realloc,String::append,Log_event::read_log_event,mysql_binlog_send,dispatch_command,handle_one_connection,start_thread,clone
      1 __lll_mutex_lock_wait,_L_mutex_lock_1133,pthread_mutex_lock,safe_mutex_lock,_sanity,_mymalloc,_myrealloc,mi_alloc_rec_buff,mi_open,ha_myisam::open,handler::ha_open,open_tmp_table,create_tmp_table,select_union::create_result_table,mysql_derived_prepare,mysql_handle_derived,open_and_lock_tables,mysql_execute_command,mysql_parse,dispatch_command,handle_one_connection,start_thread,clone
      1 __lll_mutex_lock_wait,_L_mutex_lock_1133,pthread_mutex_lock,safe_mutex_lock,_sanity,_mymalloc,init_dynamic_array,QUICK_RANGE_SELECT,get_quick_select,TRP_RANGE::make_quick,SQL_SELECT::test_quick_select,make_join_statistics,JOIN::optimize,mysql_select,mysql_derived_filling,mysql_handle_derived,open_and_lock_tables,mysql_execute_command,mysql_parse,dispatch_command,handle_one_connection,start_thread,clone
      1 __lll_mutex_lock_wait,_L_mutex_lock_1133,pthread_mutex_lock,safe_mutex_lock,_mymalloc,alloc_root,MYSQLparse,mysql_make_view,open_unireg_entry,open_table,open_tables,open_and_lock_tables,mysql_execute_command,mysql_parse,dispatch_command,handle_one_connection,start_thread,clone
      1 __lll_mutex_lock_wait,_L_mutex_lock_107,pthread_mutex_lock,safe_mutex_lock,mi_open,ha_myisam::open,handler::ha_open,open_tmp_table,create_tmp_table,select_union::create_result_table,mysql_derived_prepare,mysql_handle_derived,open_and_lock_tables,mysql_execute_command,mysql_parse,dispatch_command,handle_one_connection,start_thread,clone
      1 do_sigwait,sigwait,signal_hand,start_thread,clone
EOF

aggregate_stacktrace 0 samples/stacktrace-001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

# ############################################################################
TEST_NAME="stacktrace-002.txt"
# ############################################################################
cat > $TMPDIR/expected <<EOF
   2387 pthread_cond_wait,open_table,open_tables,open_and_lock_tables_derived,execute_sqlcom_select,mysql_execute_command,mysql_parse,dispatch_command,do_command,handle_one_connection,start_thread,clone
      5 pthread_cond_wait,open_table,open_tables,open_and_lock_tables_derived,mysql_insert,mysql_execute_command,mysql_parse,dispatch_command,do_command,handle_one_connection,start_thread,clone
      4 pthread_cond_wait,os_event_wait_low,os_aio_simulated_handle,fil_aio_wait,io_handler_thread,start_thread,clone
      4 pthread_cond_wait,open_table,open_tables,open_and_lock_tables_derived,mysql_delete,mysql_execute_command,mysql_parse,dispatch_command,do_command,handle_one_connection,start_thread,clone
      1 select,os_thread_sleep,srv_master_thread,start_thread,clone
      1 select,os_thread_sleep,srv_lock_timeout_and_monitor_thread,start_thread,clone
      1 select,os_thread_sleep,srv_error_monitor_thread,start_thread,clone
      1 select,handle_connections_sockets,main,select
      1 read,my_real_read,my_net_read,do_command,handle_one_connection,start_thread,clone
      1 pthread_cond_wait,cache_thread,one_thread_per_connection_end,handle_one_connection,start_thread,clone
      1 free,ut_free,page_cur_insert_rec_low,btr_cur_optimistic_insert,row_ins_index_entry_low,row_ins_index_entry,row_ins,row_ins_step,row_insert_for_mysql,ha_innobase::write_row,handler::ha_write_row,ha_partition::copy_partitions,ha_partition::change_partitions,handler::ha_change_partitions,mysql_change_partitions,fast_alter_partition_table,mysql_alter_table,mysql_execute_command,mysql_parse,dispatch_command,do_command,handle_one_connection,start_thread,clone
      1 do_sigwait,sigwait,signal_hand,start_thread,clone
EOF

aggregate_stacktrace 0 samples/stacktrace-002.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

# ############################################################################
TEST_NAME="stacktrace-003.txt"
# ############################################################################
cat > $TMPDIR/expected <<EOF
     35 pthread_cond_wait,end_thread,handle_one_connection,start_thread,clone
     20 read,read,vio_read,my_real_read,my_net_read,handle_one_connection,start_thread,clone
     18 pthread_cond_wait,os_event_wait_low,os_aio_simulated_handle,fil_aio_wait,io_handler_thread,start_thread,clone
      3 pthread_cond_wait,MYSQL_LOG::wait_for_update,mysql_binlog_send,dispatch_command,handle_one_connection,start_thread,clone
      1 select,os_thread_sleep,srv_master_thread,start_thread,clone
      1 select,os_thread_sleep,srv_lock_timeout_and_monitor_thread,start_thread,clone
      1 select,os_thread_sleep,srv_error_monitor_thread,start_thread,clone
      1 select,handle_connections_sockets,main
      1 do_sigwait,sigwait,signal_hand,start_thread,clone
      1 btr_search_guess_on_hash,btr_cur_search_to_nth_level,btr_pcur_open_with_no_init,row_search_for_mysql,ha_innobase::index_read,join_read_always_key,sub_select,evaluate_join_record,sub_select,evaluate_join_record,sub_select,evaluate_join_record,sub_select,evaluate_join_record,sub_select,evaluate_join_record,sub_select,do_select,JOIN::exec,mysql_select,handle_select,mysql_execute_command,mysql_parse,dispatch_command,handle_one_connection,start_thread,clone
      1 btr_cur_search_to_nth_level,btr_estimate_n_rows_in_range,ha_innobase::records_in_range,check_quick_keys,check_quick_keys,check_quick_keys,check_quick_keys,check_quick_keys,check_quick_keys,check_quick_keys,check_quick_keys,check_quick_keys,check_quick_keys,check_quick_keys,check_quick_select,get_key_scans_params,SQL_SELECT::test_quick_select,get_quick_record_count,make_join_statistics,JOIN::optimize,mysql_select,handle_select,mysql_execute_command,mysql_parse,dispatch_command,handle_one_connection,start_thread,clone
EOF

aggregate_stacktrace 0 samples/stacktrace-003.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

# ############################################################################
TEST_NAME="stacktrace-003-b.txt"
# ############################################################################
cat > $TMPDIR/expected <<EOF
     35 pthread_cond_wait,end_thread
     20 read,read
     18 pthread_cond_wait,os_event_wait_low
      3 select,os_thread_sleep
      3 pthread_cond_wait,MYSQL_LOG::wait_for_update
      1 select,handle_connections_sockets
      1 do_sigwait,sigwait
      1 btr_search_guess_on_hash,btr_cur_search_to_nth_level
      1 btr_cur_search_to_nth_level,btr_estimate_n_rows_in_range
EOF

aggregate_stacktrace 2 samples/stacktrace-003.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

# ############################################################################
TEST_NAME="stacktrace-004.txt"
# ############################################################################
cat > $TMPDIR/expected <<EOF
     33 pthread_cond_wait,boost::condition_variable::wait,Queue::pop,Worker::work,boost::_mfi::mf0::operator,boost::_bi::list1::operator,boost::_bi::bind_t::operator,boost::detail::thread_data::run,thread_proxy,start_thread,clone,??
      1 StringBuilder::length,Parser::add,Parser::try_parse_query,Parser::parse_block,Parser::work,boost::_mfi::mf0::operator,boost::_bi::list1::operator,boost::_bi::bind_t::operator,boost::detail::thread_data::run,thread_proxy,start_thread,clone,??
      1 pthread_cond_wait,boost::thread::join,LogReader::wait,Replay::wait,main
      1 pthread_cond_wait,boost::condition_variable::wait,Queue::push,LogReader::work,boost::_mfi::mf0::operator,boost::_bi::list1::operator,boost::_bi::bind_t::operator,boost::detail::thread_data::run,thread_proxy,start_thread,clone,??
      1 pthread_cond_wait,boost::condition_variable::wait,Queue::pop,Reporter::work,boost::_mfi::mf0::operator,boost::_bi::list1::operator,boost::_bi::bind_t::operator,boost::detail::thread_data::run,thread_proxy,start_thread,clone,??
EOF

aggregate_stacktrace 0 samples/stacktrace-004.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

# ############################################################################
TEST_NAME="stacktrace-005.txt"
# ############################################################################
cat > $TMPDIR/expected <<EOF
     32 read,vio_read_buff,libmysqlclient::??,my_net_read,cli_safe_read,libmysqlclient::??,mysql_real_query,Connection::run,Worker::work,thread_proxy,start_thread,clone,??
      1 pthread_cond_wait,LogReader::work,thread_proxy,start_thread,clone,??
      1 pthread_cond_wait,boost::thread::join,main
      1 pthread_cond_wait,boost::condition_variable::wait,Worker::work,thread_proxy,start_thread,clone,??
      1 pthread_cond_wait,boost::condition_variable::wait,Reporter::work,thread_proxy,start_thread,clone,??
      1 pthread_cond_wait,boost::condition_variable::wait,Queue::push,Parser::work,thread_proxy,start_thread,clone,??
EOF

aggregate_stacktrace 0 samples/stacktrace-005.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
