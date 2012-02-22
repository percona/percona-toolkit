#!/bin/bash

TEST=3
TMPDIR=$TEST_TMPDIR

cat <<EOF > $TMPDIR/expected
   master semisync status | 0
       master trace level | 32, net wait (more information about network waits)
master timeout in milliseconds | 10000
  master waits for slaves | ON
           master clients | 0
 master net_avg_wait_time | 0
     master net_wait_time | 0
         master net_waits | 0
          master no_times | 0
             master no_tx | 0
 master timefunc_failures | 0
  master tx_avg_wait_time | 0
      master tx_wait_time | 0
          master tx_waits | 0
master wait_pos_backtraverse | 0
     master wait_sessions | 0
            master yes_tx | 0
EOF

_semi_sync_stats_for "master" samples/mysql-variables-with-semisync.txt > $TMPDIR/got
no_diff $TMPDIR/expected $TMPDIR/got
