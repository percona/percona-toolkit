#/bin/bash

TESTS=1
TMPDIR=$TEST_TMPDIR

test_format_innodb () {
   local NAME_VAL_LEN=25
   cat <<EOF > $TMPDIR/expected
                  Version | 1.0.17-13.2
         Buffer Pool Size | 128.0M
         Buffer Pool Fill | 1%
        Buffer Pool Dirty | 0%
           File Per Table | OFF
                Page Size | 16k
            Log File Size | 2 * 1.5G = 3.1G
          Log Buffer Size | 8M
             Flush Method | 0
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

   _innodb samples/temp001/percona-toolkit-mysql-variables samples/temp001/percona-toolkit-mysql-status > $TMPDIR/got
   no_diff $TMPDIR/expected $TMPDIR/got
}

test_format_innodb
