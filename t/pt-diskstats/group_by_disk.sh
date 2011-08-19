#!/bin/bash

# This test file must be ran by util/test-bash-functions.

TESTS=5

TEST_NAME="diskstats-001.txt"
cat <<EOF > $TMPDIR/expected
  #ts device          rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg
  {4} ram0             0.0     0.0     0.0     0%    0.0     0.0     0.0     0.0     0.0     0%    0.0     0.0   0%      0
  {4} cciss/c0d0       0.0     0.0     0.0     0%    0.0     0.0    17.7    56.2     0.5    86%    0.0     0.6   0%      0
  {4} cciss/c0d0p1     0.0     0.0     0.0     0%    0.0     0.0     0.0     0.0     0.0     0%    0.0     0.0   0%      0
  {4} cciss/c0d0p2     0.0     0.0     0.0     0%    0.0     0.0    17.7    56.2     0.5    86%    0.0     0.6   0%      0
  {4} cciss/c0d1     458.1    43.0     9.6     0%   11.5    25.1   985.0    48.4    23.3     0%    0.1     0.1 102%      0
  {4} cciss/c1d0       0.0     0.0     0.0     0%    0.0     0.0     0.0     0.0     0.0     0%    0.0     0.0   0%      0
  {4} dm-0             0.0     0.0     0.0     0%    0.0     0.0    99.3     8.0     0.4     0%    0.1     0.7   0%      0
  {4} md0              0.0     0.0     0.0     0%    0.0     0.0     0.0     0.0     0.0     0%    0.0     0.0   0%      0
EOF
group_by_disk samples/diskstats-001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected


TEST_NAME="diskstats-005.txt"
cat <<EOF > $TMPDIR/expected
  #ts device    rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg
  {5} sda3    1394.1    32.0    21.8     1%    0.5     0.4    98.8    62.8     3.0    48%    0.0     0.3  41%      0
  {5} sda4    1394.1    32.0    21.8     1%    0.5     0.4    98.8    62.8     3.0    48%    0.0     0.3  41%      0
EOF
group_by_disk samples/diskstats-005.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected


TEST_NAME="diskstats-005.txt with TS"
cat <<EOF > $TMPDIR/expected
  #ts device    rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg
  {5} sda3    1394.1    32.0    21.8     1%    0.5     0.4    98.8    62.8     3.0    48%    0.0     0.3  41%      0
  {5} sda4    1394.1    32.0    21.8     1%    0.5     0.4    98.8    62.8     3.0    48%    0.0     0.3  41%      0
EOF

cat > $TMPDIR/in <<EOF
TS 1298130002.073935000
EOF
cat samples/diskstats-005.txt >> $TMPDIR/in
group_by_disk $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected


TEST_NAME="no output"
cat <<EOF > $TMPDIR/expected
EOF

cat <<EOF > $TMPDIR/in
TS 1297205887.156653000
   1    0 ram0 0 0 0 0 0 0 0 0 0 0 0
TS 1297205888.161613000
EOF
group_by_disk $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected


TEST_NAME="timestamps"
cat <<EOF > $TMPDIR/expected
  #ts device    rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg
  {1} ram0       1.0     1.0     0.0    50%    0.0     1.0     1.0     1.0     0.0    50%    0.0     1.0   0%      0
EOF

cat <<EOF > $TMPDIR/in
   1    0 ram0 0 0 0 0 0 0 0 0 0 0 0
TS 1297205887.156653000
   1    0 ram0 1 1 1 1 1 1 1 1 1 1 1
TS 1297205888.161613000
EOF
group_by_disk $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
