#!/usr/bin/env bash

TESTS=4
TMPDIR=$TEST_TMPDIR

# ############################################################################
TEST_NAME="innodb-status.001.txt"
# ############################################################################
cat <<EOF > $TMPDIR/expected
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

format_innodb_status samples/innodb-status.001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

# ############################################################################
TEST_NAME="innodb-status.002.txt"
# ############################################################################
cat <<'EOF' > $TMPDIR/expected
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

format_innodb_status samples/innodb-status.002.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

# ############################################################################
TEST_NAME="innodb-status.003.txt"
# ############################################################################
cat <<'EOF' > $TMPDIR/expected
      Checkpoint Age | 0k
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

format_innodb_status samples/innodb-status.003.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

# ############################################################################
TEST_NAME="innodb-status.004.txt" 
# ############################################################################
cat <<'EOF' > $TMPDIR/expected
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

format_innodb_status samples/innodb-status.004.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
