#!/usr/bin/env bash

plan 44

. "$LIB_DIR/alt_cmds.sh"
. "$LIB_DIR/log_warn_die.sh"
. "$LIB_DIR/summary_common.sh"
. "$LIB_DIR/report_formatting.sh"
. "$LIB_DIR/report_mysql_info.sh"

PT_TMPDIR="$TEST_PT_TMPDIR"
PATH="$PATH:$PERCONA_TOOLKIT_SANDBOX/bin"
TOOL="pt-mysql-summary"

samples="$PERCONA_TOOLKIT_BRANCH/t/pt-mysql-summary/samples"
NAME_VAL_LEN=20
# ###########################################################################
# table_cache
# ###########################################################################

rm $PT_TMPDIR/table_cache_tests 2>/dev/null
touch $PT_TMPDIR/table_cache_tests

is                                                  \
   $(get_table_cache "$PT_TMPDIR/table_cache_tests")   \
   0                                                \
   "0 if neither table_cache nor table_open_cache are present"

cat <<EOF > $PT_TMPDIR/table_cache_tests
table_cache       5
table_open_cache  4
EOF

is                                                 \
   $(get_table_cache "$PT_TMPDIR/table_cache_tests")  \
   4                                               \
   "If there's a table_open_cache present, uses that"

cat <<EOF > $PT_TMPDIR/table_cache_tests
table_cache       5
EOF

is                                                 \
   $(get_table_cache "$PT_TMPDIR/table_cache_tests")  \
   5                                               \
   "Otherwise, defaults to table_cache"

# ###########################################################################
# summarize_processlist
# ###########################################################################

cat <<EOF > $PT_TMPDIR/expected

  Command                        COUNT(*) Working SUM(Time) MAX(Time)
  ------------------------------ -------- ------- --------- ---------
  Binlog Dump                           1       1   9000000   9000000
  Connect                               2       2   6000000   5000000
  Query                                 2       2         0         0
  Sleep                               150       0    150000     20000

  User                           COUNT(*) Working SUM(Time) MAX(Time)
  ------------------------------ -------- ------- --------- ---------
  acjcxx                                4       0         0         0
  aecac                                 1       0         0         0
  babeecc                              20       0         0         0
  centous                               2       0         0         0
  crcpcpc                               2       0         0         0
  crgcp4c                               3       0         0         0
  eanecj                               30       1         0         0
  ebace                                10       0         0         0
  etace                                80       0         0         0
  goate                                 8       0         0         0
  qjveec                                1       0         0         0
  repl                                  1       1   9000000   9000000
  root                                  1       1         0         0
  system user                           2       2   6000000   5000000

  Host                           COUNT(*) Working SUM(Time) MAX(Time)
  ------------------------------ -------- ------- --------- ---------
  10.14.82.196                          6       0         0         0
  10.14.82.202                         20       0         0         0
  10.17.85.100                          9       0         0         0
  10.17.85.74                           1       1   9000000   9000000
  10.17.85.86                          35       0         0         0
  10.17.85.88                           5       0         0         0
  10.17.85.90                          10       0         0         0
  10.36.34.66                          35       1         0         0
                                        2       2   6000000   5000000
  localhost                             1       1         0         0
  someserver.woozle.com11               1       0         0         0
  someserver.woozle.com14               1       0         0         0
  someserver.woozle.com                40       0         0         0

  db                             COUNT(*) Working SUM(Time) MAX(Time)
  ------------------------------ -------- ------- --------- ---------
  aetecjc                             175       1         0         0
  NULL                                  4       4  15000000   9000000

  State                          COUNT(*) Working SUM(Time) MAX(Time)
  ------------------------------ -------- ------- --------- ---------
                                      150       0         0         0
  Has read all relay log; waitin        1       1    300000    300000
  Has sent all binlog to slave;         1       1   9000000   9000000
  NULL                                  2       2         0         0
  Waiting for master to send eve        1       1   5000000   5000000

EOF

summarize_processlist "$samples/processlist-001.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "summarize_processlist" \
   || cat "$PT_TMPDIR/got" "$PT_TMPDIR/expected" >&2

# ###########################################################################
# summarize_binlogs
# ###########################################################################
NAME_VAL_LEN=25
cat <<EOF > "$PT_TMPDIR/expected"
                  Binlogs | 20
               Zero-Sized | 3
               Total Size | 6.5G
EOF

summarize_binlogs "$samples/mysql-master-logs-001.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/expected" "$PT_TMPDIR/got" "summarize_binlogs"

# ###########################################################################
# Reporting semisync replication
# ###########################################################################

cat <<EOF > "$PT_TMPDIR/expected"
   master semisync status | 
       master trace level | 32, net wait (more information about network waits)
master timeout in milliseconds | 10000
  master waits for slaves | ON
           master clients | 
 master net_avg_wait_time | 
     master net_wait_time | 
         master net_waits | 
          master no_times | 
             master no_tx | 
 master timefunc_failures | 
  master tx_avg_wait_time | 
      master tx_wait_time | 
          master tx_waits | 
master wait_pos_backtraverse | 
     master wait_sessions | 
            master yes_tx | 
EOF

_semi_sync_stats_for "master" "$samples/mysql-variables-with-semisync.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/expected" "$PT_TMPDIR/got" "semisync replication"

# ###########################################################################
# pretty_print_cnf_file
# ###########################################################################

cat <<EOF > $PT_TMPDIR/expected

[mysqld]
datadir                             = /mnt/data/mysql
socket                              = /mnt/data/mysql/mysql.sock
old_passwords                       = 1
ssl-key                             = /opt/mysql.pdns/.cert/server-key.pem
ssl-cert                            = /opt/mysql.pdns/.cert/server-cert.pem
ssl-ca                              = /opt/mysql.pdns/.cert/ca-cert.pem
innodb_buffer_pool_size             = 16M
innodb_flush_method                 = O_DIRECT
innodb_log_file_size                = 64M
innodb_log_buffer_size              = 1M
innodb_flush_log_at_trx_commit      = 2
innodb_file_per_table               = 1
ssl                                 = 1
server-id                           = 1
log-bin                             = sl1-bin
wsrep_provider_options              = "gcache.size=64M;base_host=10.1.2.102; base_port=4567; cert.log_conflicts=no;etc=etc;"

[mysql.server]
user                                = mysql
basedir                             = /mnt/data

[mysqld_safe]
log-error                           = /var/log/mysqld.log
pid-file                            = /var/run/mysqld/mysqld.pid

[mysql]

[xtrabackup]
target-dir                          = /data/backup
EOF

pretty_print_cnf_file "$samples/my.cnf-001.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "pretty_print_cnf_file"


# TODO BUG NUMBER#
cp "$samples/my.cnf-001.txt" "$PT_TMPDIR/test_pretty_print_cnf_file"
echo "some_var_yadda=0" >> "$PT_TMPDIR/test_pretty_print_cnf_file"
echo "some_var_yadda                      = 0" >> "$PT_TMPDIR/expected"

pretty_print_cnf_file "$PT_TMPDIR/test_pretty_print_cnf_file" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "pretty_print_cnf_file, bug XXXXXX"


# ###########################################################################
# plugin_status
# ###########################################################################

cat <<EOF > $PT_TMPDIR/plugins
binlog   ACTIVE   STORAGE ENGINE NULL  GPL
partition   ACTIVE   STORAGE ENGINE NULL  GPL
ARCHIVE  ACTIVE   STORAGE ENGINE NULL  GPL
BLACKHOLE   ACTIVE   STORAGE ENGINE NULL  GPL
CSV   ACTIVE   STORAGE ENGINE NULL  GPL
FEDERATED   DISABLED STORAGE ENGINE NULL  GPL
MEMORY   ACTIVE   STORAGE ENGINE NULL  GPL
InnoDB   ACTIVE   STORAGE ENGINE NULL  GPL
MyISAM   ACTIVE   STORAGE ENGINE NULL  GPL
MRG_MYISAM  ACTIVE   STORAGE ENGINE NULL  GPL
EOF

is \
   "$(get_plugin_status $PT_TMPDIR/plugins InnoDB )"  \
   "ACTIVE"                                  \
   "Sanity test, finds InnoDB as active"

is \
   "$(get_plugin_status $PT_TMPDIR/plugins some_plugin_that_doesnt_exist )"  \
   "Not found"                                  \
   "Doesn't find a nonexistent plugin"

echo "INNODB_CMP  ACTIVE" >> $PT_TMPDIR/plugins
is \
   "$(get_plugin_status $PT_TMPDIR/plugins "INNODB_CMP" )"  \
   "ACTIVE"

cat <<EOF > $PT_TMPDIR/plugins
binlog   ACTIVE   STORAGE ENGINE NULL  GPL
mysql_native_password   ACTIVE   AUTHENTICATION NULL  GPL
mysql_old_password   ACTIVE   AUTHENTICATION NULL  GPL
MRG_MYISAM  ACTIVE   STORAGE ENGINE NULL  GPL
MyISAM   ACTIVE   STORAGE ENGINE NULL  GPL
CSV   ACTIVE   STORAGE ENGINE NULL  GPL
MEMORY   ACTIVE   STORAGE ENGINE NULL  GPL
FEDERATED   DISABLED STORAGE ENGINE NULL  GPL
ARCHIVE  ACTIVE   STORAGE ENGINE NULL  GPL
BLACKHOLE   ACTIVE   STORAGE ENGINE NULL  GPL
InnoDB   ACTIVE   STORAGE ENGINE NULL  GPL
INNODB_TRX  ACTIVE   INFORMATION SCHEMA   NULL  GPL
INNODB_LOCKS   ACTIVE   INFORMATION SCHEMA   NULL  GPL
INNODB_LOCK_WAITS ACTIVE   INFORMATION SCHEMA   NULL  GPL
INNODB_CMP  ACTIVE   INFORMATION SCHEMA   NULL  GPL
INNODB_CMP_RESET  ACTIVE   INFORMATION SCHEMA   NULL  GPL
INNODB_CMPMEM  ACTIVE   INFORMATION SCHEMA   NULL  GPL
INNODB_CMPMEM_RESET  ACTIVE   INFORMATION SCHEMA   NULL  GPL
PERFORMANCE_SCHEMA   ACTIVE   STORAGE ENGINE NULL  GPL
partition   ACTIVE   STORAGE ENGINE NULL  GPL
EOF

is \
   "$(get_plugin_status $PT_TMPDIR/plugins "INNODB_CMP" )"  \
   "ACTIVE"                                              \
   "Multiple plugins with the same prefix"

# ###########################################################################
# parse_mysqld_instances
# ###########################################################################

_NO_FALSE_NEGATIVES=1

cat <<EOF > $PT_TMPDIR/expected
  Port  Data Directory             Nice OOM Socket
  ===== ========================== ==== === ======
   3306 /var/lib/mysql             ?    ?   /var/run/mysqld/mysqld.sock
  12345 /tmp/12345/data            ?    ?   /tmp/12345/mysql_sandbox12345.sock
  12346 /tmp/12346/data            ?    ?   /tmp/12346/mysql_sandbox12346.sock
EOF
touch "$PT_TMPDIR/empty"
parse_mysqld_instances "$samples/ps-mysqld-001.txt" "$PT_TMPDIR/empty" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "ps-mysqld-001.txt"

cat <<EOF > "$PT_TMPDIR/expected"
  Port  Data Directory             Nice OOM Socket
  ===== ========================== ==== === ======
        /var/lib/mysql             ?    ?   /var/lib/mysql/mysql.sock
EOF
parse_mysqld_instances "$samples/ps-mysqld-002.txt" "$PT_TMPDIR/empty" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "ps-mysqld-002.txt"

#parse_mysqld_instances
cat <<EOF > $PT_TMPDIR/expected
  Port  Data Directory             Nice OOM Socket
  ===== ========================== ==== === ======
   3306 /mnt/data-store/mysql/data ?    ?   /tmp/mysql.sock
EOF
parse_mysqld_instances "$samples/ps-mysqld-003.txt" "$PT_TMPDIR/empty" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "ps-mysqld-003.txt"

cat <<EOF > "$PT_TMPDIR/expected"
  Port  Data Directory             Nice OOM Socket
  ===== ========================== ==== === ======
        /var/db/mysql              ?    ?   
EOF

cat <<EOF > "$PT_TMPDIR/in"
mysql   767  0.0  0.9  3492  1100  v0  I     3:01PM   0:00.07 /bin/sh /usr/local/bin/mysqld_safe --defaults-extra-file=/var/db/mysql/my.cnf --user=mysql --datadir=/var/db/mysql --pid-file=/var/db/mysql/freebsd.hsd1.va.comcast.net..pid
mysql   818  0.0 17.4 45292 20584  v0  I     3:01PM   0:02.28 /usr/local/libexec/mysqld --defaults-extra-file=/var/db/mysql/my.cnf --basedir=/usr/local --datadir=/var/db/mysql --user=mysql --log-error=/var/db/mysql/freebsd.hsd1.va.comcast.net..err --pid-file=/var/db/mysql/freebsd.hsd1.va.comcast.net..pid
EOF
parse_mysqld_instances "$PT_TMPDIR/in" "$PT_TMPDIR/empty" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "parse_mysqld_instances"

cat <<EOF > "$PT_TMPDIR/expected"
  Port  Data Directory             Nice OOM Socket
  ===== ========================== ==== === ======
  12345 /tmp/12345/data            ?    ?   /tmp/12345/mysql_sandbox12345.sock
  12346 /tmp/12346/data            ?    ?   /tmp/12346/mysql_sandbox12346.sock
  12347 /tmp/12347/data            ?    ?   /tmp/12347/mysql_sandbox12347.sock
EOF
parse_mysqld_instances "$samples/ps-mysqld-006.txt" "$PT_TMPDIR/empty" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "ps-mysqld-006.txt (uses --defaults-file)"

# ###########################################################################
# get_mysql_*
# ###########################################################################
NAME_VAL_LEN=20

cp $samples/mysql-variables-001.txt $PT_TMPDIR/mysql-variables
is \
   $(get_mysql_timezone "$PT_TMPDIR/mysql-variables") \
   "EDT" \
   "get_mysql_timezone"

cat <<EOF > $PT_TMPDIR/expected
2010-05-27 11:38 (up 0+02:08:52)
EOF
cp $samples/mysql-status-001.txt $PT_TMPDIR/mysql-status
uptime="$(get_var Uptime $PT_TMPDIR/mysql-status)"
current_time="$(echo -e "2010-05-27 11:38\n")"
get_mysql_uptime "${uptime}" "${current_time}" > $PT_TMPDIR/got
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "get_mysql_uptime"

cat <<EOF > $PT_TMPDIR/expected
             Version | 5.0.51a-24+lenny2 (Debian)
            Built On | debian-linux-gnu i486
EOF
cp "$samples/mysql-variables-001.txt" "$PT_TMPDIR/mysql-variables"
get_mysql_version "$PT_TMPDIR/mysql-variables" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "get_mysql_version"

# ###########################################################################
# format_status_variables
# ###########################################################################

cat <<EOF > "$PT_TMPDIR/expected"
Variable                                Per day  Per second      5 secs
Bytes_received                          8000000         100            
Bytes_sent                             35000000         400            
Com_admin_commands                           20                        
Com_change_db                              1000                        
Com_delete                                 8000                        
Com_insert                                 8000                        
Com_lock_tables                             200                        
Com_replace                                1250                        
Com_select                                22500                        
Com_set_option                            22500                        
Com_show_binlogs                             10                        
Com_show_create_db                          400                        
Com_show_create_table                      7000                        
Com_show_databases                          125                        
Com_show_fields                            7000                        
Com_show_innodb_status                      300                        
Com_show_open_tables                         10                        
Com_show_processlist                        300                        
Com_show_slave_status                       300                        
Com_show_status                             350                        
Com_show_storage_engines                     10                        
Com_show_tables                             400                        
Com_show_triggers                          7000                        
Com_show_variables                          450                        
Com_truncate                                300                        
Com_unlock_tables                           250                        
Com_update                                  900                        
Connections                                2500                        
Created_tmp_disk_tables                   15000                        
Created_tmp_files                            60                        
Created_tmp_tables                        22500                        
Flush_commands                               10                        
Handler_delete                             8000                        
Handler_read_first                         2250                        
Handler_read_key                          30000                        
Handler_read_next                         15000                        
Handler_read_rnd                           9000                        
Handler_read_rnd_next                    300000           3            
Handler_update                            17500                        
Handler_write                            250000           2            
Innodb_buffer_pool_pages_data               225                        
Innodb_buffer_pool_pages_free              5000                        
Innodb_buffer_pool_pages_total             6000                        
Innodb_buffer_pool_read_ahead_rnd            10                        
Innodb_buffer_pool_read_requests           2250                        
Innodb_buffer_pool_reads                    150                        
Innodb_data_fsyncs                           35                        
Innodb_data_read                       30000000         350            
Innodb_data_reads                           300                        
Innodb_data_writes                           35                        
Innodb_data_written                       17500                        
Innodb_log_writes                            10                        
Innodb_os_log_fsyncs                         35                        
Innodb_os_log_written                      6000                        
Innodb_page_size                         175000           2            
Innodb_pages_read                           225                        
Key_blocks_unused                        150000           1            
Key_blocks_used                             175                        
Key_read_requests                        100000           1            
Key_reads                                   600                        
Key_write_requests                        70000                        
Key_writes                                17500                        
Max_used_connections                         45                        
Open_files                                 1500                        
Open_tables                                 700                        
Opened_tables                             15000                        
Qcache_free_blocks                           80                        
Qcache_free_memory                    175000000        2250            
Qcache_hits                                8000                        
Qcache_inserts                            20000                        
Qcache_not_cached                         10000                        
Qcache_queries_in_cache                     225                        
Qcache_total_blocks                         600                        
Questions                                100000           1            
Select_scan                               25000                        
Sort_rows                                  8000                        
Sort_scan                                   300                        
Table_locks_immediate                     50000                   17500
Table_locks_waited                           10                       1
Threads_cached                               35                        
Threads_connected                            10                        
Threads_created                              45                        
Threads_running                              10                        
Uptime                                    90000           1           1
Uptime_since_flush_status                 90000           1            
EOF

join "$samples/mysql-status-001.txt" "$samples/mysql-status-002.txt" > "$PT_TMPDIR/in"
format_status_variables "$PT_TMPDIR/in" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "format_status_variables"

# ###########################################################################
# format_overall_db_stats
# ###########################################################################

cat <<EOF > "$PT_TMPDIR/expected"

  Database Tables Views SPs Trigs Funcs   FKs Partn
  mysql        17                                  
  sakila       17     7   3     6     3    22     1

  Database MyISAM InnoDB
  mysql        17       
  sakila        2     15

  Database BTREE FULLTEXT
  mysql       24         
  sakila      63        1

             c   t   s   e   t   s   i   t   b   l   b   v   d   y   d   m
             h   i   e   n   i   m   n   e   l   o   i   a   a   e   e   e
             a   m   t   u   n   a   t   x   o   n   g   r   t   a   c   d
             r   e       m   y   l       t   b   g   i   c   e   r   i   i
                 s           i   l               b   n   h   t       m   u
                 t           n   i               l   t   a   i       a   m
                 a           t   n               o       r   m       l   i
                 m               t               b           e           n
                 p                                                       t
  Database === === === === === === === === === === === === === === === ===
  mysql     38   5   5  69   2   3  16   2   4   1   2                    
  sakila     1  15   1   3  19  26   3   4   1          45   4   1   7   2

EOF
format_overall_db_stats "$samples/mysql-schema-001.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected"

cat <<EOF > $PT_TMPDIR/expected

  Database Tables Views SPs Trigs Funcs   FKs Partn
  {chosen}      1                                  

  Database InnoDB
  {chosen}      1

  Database BTREE
  {chosen}     2

             t   v
             i   a
             n   r
             y   c
             i   h
             n   a
             t   r
  Database === ===
  {chosen}   1   1

EOF
format_overall_db_stats "$samples/mysql-schema-002.txt" > "$PT_TMPDIR/got"
no_diff \
   "$PT_TMPDIR/got" \
   "$PT_TMPDIR/expected" \
   "format_overall_db_stats: single DB without CREATE DATABASE nor USE db defaults to {chosen}"

# ###########################################################################
# format_innodb_status
# ###########################################################################

cat <<EOF > $PT_TMPDIR/expected
      Checkpoint Age | 619k
        InnoDB Queue | 0 queries inside InnoDB, 0 queries in queue
  Oldest Transaction | 3 Seconds
    History List Len | 255
          Read Views | 23
    Undo Log Entries | 0 transactions, 0 total undo, 0 max undo
   Pending I/O Reads | 14 buf pool reads, 6 normal AIO, 0 ibuf AIO, 23 preads
  Pending I/O Writes | 63 buf pool (63 LRU, 0 flush list, 0 page); 0 AIO, 0 sync, 0 log IO (1 log, 0 chkp); 0 pwrites
 Pending I/O Flushes | 0 buf pool, 1 log
  Transaction States | 1xACTIVE
Semaphore Waits
     69 btr/btr0cur.c line 457
     47 btr/btr0cur.c line 523
     17 trx/trx0trx.c line 1621
     12 row/row0sel.c line 3549
      4 lock/lock0lock.c line 4944
      3 lock/lock0lock.c line 5316
      2 lock/lock0lock.c line 3224
      2 btr/btr0sea.c line 1032
      1 trx/trx0trx.c line 738
      1 row/row0sel.c line 4574
      1 lock/lock0lock.c line 5163
      1 lock/lock0lock.c line 3249
      1 ./include/btr0btr.ic line 53
      1 fsp/fsp0fsp.c line 3395
      1 btr/btr0cur.c line 672
      1 btr/btr0cur.c line 450
Semaphore Holders
     66 thread id 139960165583184
     45 thread id 139960567171408
      4 thread id 139960404199760
      1 thread id 139961215367504
      1 thread id 139960969292112
      1 thread id 139960676096336
Mutexes/Locks Waited For
     65 lock on RW-latch at 0x905d33d0 '&new_index->lock'
     45 lock on RW-latch at 0x7f4bedbf8810 '&block->lock'
     30 Mutex at 0xf89ab0 '&kernel_mutex'
     15 lock on RW-latch at 0x90075530 '&btr_search_latch'
      4 lock on RW-latch at 0x90a42ca0 '&new_index->lock'
      1 lock on RW-latch at 0x90fe1c80 '&new_index->lock'
      1 lock on RW-latch at 0x90078f10 '&space->latch'
      1 lock on RW-latch at 0x7f4c0d3abba8 '&block->lock'
      1 lock on RW-latch at 0x7f4bfc558040 '&block->lock'
      1 lock on RW-latch at 0x7f4bd0a8c8d0 '&block->lock'
EOF

format_innodb_status $samples/innodb-status.001.txt > $PT_TMPDIR/got
no_diff $PT_TMPDIR/got $PT_TMPDIR/expected "innodb-status.001.txt" \
   || cat "$PT_TMPDIR/got" "$PT_TMPDIR/expected" >&2

cat <<'EOF' > $PT_TMPDIR/expected
      Checkpoint Age | 348M
        InnoDB Queue | 0 queries inside InnoDB, 0 queries in queue
  Oldest Transaction | 4 Seconds
    History List Len | 426
          Read Views | 583
    Undo Log Entries | 71 transactions, 247 total undo, 46 max undo
   Pending I/O Reads | 0 buf pool reads, 0 normal AIO, 0 ibuf AIO, 0 preads
  Pending I/O Writes | 0 buf pool (0 LRU, 0 flush list, 0 page); 0 AIO, 0 sync, 0 log IO (0 log, 0 chkp); 0 pwrites
 Pending I/O Flushes | 0 buf pool, 0 log
  Transaction States | 1xACTIVE, 70xACTIVE (PREPARED)
Tables Locked
     62 `citydb`.`player_buildings`
     46 `citydb`.`players`
     22 `citydb`.`city_grid`
     17 `citydb`.`player_stats`
      6 `citydb`.`player_contracts`
      1 `citydb`.`player_achievements`
Semaphore Waits
     23 trx/trx0undo.c line 1796
     10 trx/trx0trx.c line 1888
      8 trx/trx0trx.c line 1033
      7 trx/trx0trx.c line 738
      1 lock/lock0lock.c line 3770
      1 ./include/log0log.ic line 322
Mutexes/Locks Waited For
     33 Mutex at 0x2abf68b76a18 '&rseg->mutex'
     16 Mutex at 0x48ace40 '&kernel_mutex'
      1 Mutex at 0x2abf68b6c0d0 '&log_sys->mutex'
EOF

format_innodb_status $samples/innodb-status.002.txt > $PT_TMPDIR/got
no_diff $PT_TMPDIR/got $PT_TMPDIR/expected "innodb-status.002.txt"

cat <<'EOF' > $PT_TMPDIR/expected
      Checkpoint Age | 0
        InnoDB Queue | 0 queries inside InnoDB, 0 queries in queue
  Oldest Transaction | 35 Seconds
    History List Len | 11
          Read Views | 1
    Undo Log Entries | 0 transactions, 0 total undo, 0 max undo
   Pending I/O Reads | 0 buf pool reads, 0 normal AIO, 0 ibuf AIO, 0 preads
  Pending I/O Writes | 0 buf pool (0 LRU, 0 flush list, 0 page); 0 AIO, 0 sync, 0 log IO (0 log, 0 chkp); 0 pwrites
 Pending I/O Flushes | 0 buf pool, 0 log
  Transaction States | 1xACTIVE, 1xnot started
Tables Locked
      1 `test`.`t`
EOF

format_innodb_status $samples/innodb-status.003.txt > $PT_TMPDIR/got
no_diff $PT_TMPDIR/got $PT_TMPDIR/expected "innodb-status.003.txt" \
   || cat "$PT_TMPDIR/got" "$PT_TMPDIR/expected" >&2

cat <<'EOF' > $PT_TMPDIR/expected
      Checkpoint Age | 93M
        InnoDB Queue | 9 queries inside InnoDB, 0 queries in queue
  Oldest Transaction | 263 Seconds
    History List Len | 1282
          Read Views | 10
    Undo Log Entries | 3 transactions, 276797 total undo, 153341 max undo
   Pending I/O Reads | 50 buf pool reads, 48 normal AIO, 0 ibuf AIO, 2 preads
  Pending I/O Writes | 0 buf pool (0 LRU, 0 flush list, 0 page); 0 AIO, 0 sync, 0 log IO (0 log, 0 chkp); 0 pwrites
 Pending I/O Flushes | 0 buf pool, 0 log
  Transaction States | 9xACTIVE, 57xnot started
Semaphore Waits
      3 row/row0sel.c line 3495
      2 btr/btr0sea.c line 1024
      1 btr/btr0sea.c line 1170
      1 btr/btr0cur.c line 443
      1 btr/btr0cur.c line 1501
Semaphore Holders
      7 thread id 1220999488
      1 thread id 1229429056
Mutexes/Locks Waited For
      7 lock on RW-latch at 0x2aaab42120b8 created in file btr/btr0sea.c line 139
      1 lock on RW-latch at 0x2ab2c679a550 created in file buf/buf0buf.c line 550
EOF

format_innodb_status $samples/innodb-status.004.txt > $PT_TMPDIR/got
no_diff $PT_TMPDIR/got $PT_TMPDIR/expected "innodb-status.004.txt" \
   || cat "$PT_TMPDIR/got" "$PT_TMPDIR/expected" >&2

# ###########################################################################
# section_innodb
# ###########################################################################

test_format_innodb () {
   local NAME_VAL_LEN=25
   cat <<EOF > $PT_TMPDIR/expected
                  Version | 1.0.17-13.2
         Buffer Pool Size | 128.0M
         Buffer Pool Fill | 1%
        Buffer Pool Dirty | 0%
           File Per Table | OFF
                Page Size | 16k
            Log File Size | 2 * 1.5G = 2.9G
          Log Buffer Size | 8M
             Flush Method | 
      Flush Log At Commit | 1
               XA Support | ON
                Checksums | ON
              Doublewrite | ON
          R/W I/O Threads | 4 4
             I/O Capacity | 200
       Thread Concurrency | 0
      Concurrency Tickets | 500
       Commit Concurrency | 0
      Txn Isolation Level | REPEATABLE-READ
        Adaptive Flushing | OFF
      Adaptive Checkpoint | estimate
EOF

   section_innodb "$samples/temp001/mysql-variables" "$samples/temp001/mysql-status" > "$PT_TMPDIR/got"
   no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "Format InnoDB"
}

test_format_innodb

# ###########################################################################
# format_innodb_filters
# ###########################################################################

test_format_innodb_filters () {
   local NAME_VAL_LEN=20

   cat <<EOF > $PT_TMPDIR/expected
        binlog_do_db | foo
    binlog_ignore_db | mysql,test
EOF

   format_binlog_filters "$samples/mysql-show-master-status-001.txt" > "$PT_TMPDIR/got"
   no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "Format InnoDB filters"
}

test_format_innodb_filters

# ###########################################################################
# format_overall_db_stats
# ###########################################################################

format_overall_db_stats "$samples/mysqldump-001.txt" > "$PT_TMPDIR/got"

no_diff \
   "$PT_TMPDIR/got" \
   "$samples/expected_output_format_db_stats.txt" \
   "Bug 903229: Format overall DB stats should be case-insensitive for engines"

# ###########################################################################
# report_mysql_summary
# ###########################################################################

OPT_SLEEP=1
OPT_DATABASES=""
OPT_READ_SAMPLES=""
OPT_ALL_DATABASES=""
NAME_VAL_LEN=25
report_mysql_summary "$samples/tempdir" | tail -n+3 > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$samples/expected_result_report_summary.txt"

_NO_FALSE_NEGATIVES=""
OPT_SLEEP=10
report_mysql_summary "$samples/temp002" 2>/dev/null | tail -n+3 > "$PT_TMPDIR/got"
no_diff \
   "$PT_TMPDIR/got" \
   "$samples/expected_output_temp002.txt" \
   "report_mysql_summary, dir: temp002"

report_mysql_summary "$samples/temp003" 2>/dev/null | tail -n+3 > "$PT_TMPDIR/got"
no_diff \
   "$PT_TMPDIR/got" \
   "$samples/expected_output_temp003.txt" \
   "report_mysql_summary, dir: temp003"

report_mysql_summary "$samples/temp004" 2>/dev/null | tail -n+3 > "$PT_TMPDIR/got"
no_diff \
   "$PT_TMPDIR/got" \
   "$samples/expected_output_temp004.txt" \
   "report_mysql_summary, dir: temp004"

report_mysql_summary "$samples/temp006" 2>/dev/null | tail -n+3 > "$PT_TMPDIR/got"
no_diff \
   "$PT_TMPDIR/got" \
   "$samples/expected_output_temp006.txt" \
   "report_mysql_summary, dir: temp006 (PXC, cluster node)"

report_mysql_summary "$samples/temp007" 2>/dev/null | tail -n+3 > "$PT_TMPDIR/got"
no_diff \
   "$PT_TMPDIR/got" \
   "$samples/expected_output_temp007.txt" \
   "report_mysql_summary, dir: temp007 (PXC, traditional master)"

# ###########################################################################
# parse_wsrep_provider_options
# ###########################################################################

vars_file="$samples/temp006/mysql-variables"
is \
   "$(parse_wsrep_provider_options "base_host" "$vars_file")" \
   "192.168.122.1" \
   "parse_wsrep_provider_options works for the first option"

is \
   "$(parse_wsrep_provider_options "replicator.commit_order" "$vars_file")" \
   "3" \
   "parse_wsrep_provider_options works for the last option"

is \
   "$(parse_wsrep_provider_options "pc.ignore_sb" "$vars_file")" \
   "false" \
   "parse_wsrep_provider_options works for pc.ignore_sb"

is \
   "$(parse_wsrep_provider_options "pc.ignore_quorum" "$vars_file")" \
   "false" \
   "parse_wsrep_provider_options works for pc.ignore_quorum"

is \
   "$(parse_wsrep_provider_options "gcache.name" "$vars_file")" \
   "/tmp/12345/data//galera.cache" \
   "parse_wsrep_provider_options works for gcache.name"


# ###########################################################################
# pt-mysql-summary not Percona Server 5.5-ready
# https://bugs.launchpad.net/percona-toolkit/+bug/1015590
# ###########################################################################

section_percona_server_features "$samples/percona-server-5.5-variables" > "$PT_TMPDIR/got"

no_diff \
   "$PT_TMPDIR/got" \
   "$samples/expected_output_ps-features.txt" \
   "Bug 1015590: pt-mysql-summary not Percona Server 5.5-ready"

section_percona_server_features "$samples/percona-server-5.1-variables" > "$PT_TMPDIR/got"
no_diff \
   "$PT_TMPDIR/got" \
   "$samples/expected_output_ps-5.1-features.txt" \
   "Bug 1015590: section_percona_server_features works on 5.1 with innodb_adaptive_checkpoint=none"

section_percona_server_features "$samples/percona-server-5.1-variables-martin" > "$PT_TMPDIR/got"
cp "$PT_TMPDIR/got" /tmp/dasgot
no_diff \
   "$PT_TMPDIR/got" \
   "$samples/expected_output_ps-5.1-martin.txt" \
   "section_percona_server_features works on 5.1"

# ###########################################################################
# Done
# ###########################################################################
