#!/usr/bin/env bash

# This test file must be ran by util/test-bash-functions.

TESTS=4

TEST_NAME="diskstats-001.txt"
cat <<EOF > $TMPDIR/expected
  #ts device    rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg
  2.0 {8}      466.5    44.6    10.2     0%    1.4    23.9  1184.0    42.6    24.6    18%    0.0     0.2  12%     18
  4.0 {8}      373.0    47.2     8.6     0%    1.3    27.4   592.0    45.6    13.2    16%    0.0     0.1  11%     17
  5.0 {8}      848.0    42.6    17.7     0%    2.7    25.5  1987.0    49.8    48.3     3%    0.0     0.1  22%      9
  7.0 {8}      340.0    36.6     6.1     0%    1.0    23.8  1149.5    43.4    24.3    23%    0.0     0.2  11%      5
EOF
group_by_sample samples/diskstats-001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected


TEST_NAME="input 1"
cat <<EOF > $TMPDIR/expected
  #ts device    rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg
  1.0 sda3    1406.0    32.0    21.9     1%    0.6     0.4    46.3    61.1     1.4    67%    0.0     0.3  41%      0
  2.0 sda3    1580.1    31.9    24.6     1%    0.6     0.4   163.7    62.2     5.0    36%    0.1     0.3  46%      1
  3.0 sda3    1296.7    32.0    20.2     1%    0.5     0.4    51.3    50.5     1.3    62%    0.0     0.3  42%      1
  4.1 sda3    1429.7    32.0    22.3     1%    0.5     0.3    73.9    61.0     2.2    57%    0.0     0.3  40%      0
  5.1 sda3    1258.1    32.0    19.6     1%    0.4     0.3   158.7    68.8     5.3    36%    0.1     0.4  37%      0
EOF

cat > $TMPDIR/in <<EOF
   8    3 sda3 4257315954 34043324 136169413346 1922644483 492348396 547079617 32764474048 248191881 0 1348454960 2169768832
TS 1298130003.073935000
   8    3 sda3 4257317380 34043342 136169458914 1922645044 492348443 547079711 32764476920 248191896 0 1348455373 2169769408
TS 1298130004.088149000
   8    3 sda3 4257318982 34043364 136169510082 1922645662 492348609 547079803 32764487248 248191947 1 1348455841 2169770075
TS 1298130005.102035000
   8    3 sda3 4257320297 34043384 136169552098 1922646173 492348661 547079889 32764489872 248191964 1 1348456262 2169770603
TS 1298130006.116158000
   8    3 sda3 4257321748 34043394 136169598530 1922646672 492348736 547079990 32764494448 248191983 0 1348456671 2169771121
TS 1298130007.131062000
   8    3 sda3 4257323024 34043406 136169639330 1922647105 492348897 547080080 32764505520 248192043 0 1348457045 2169771613
TS 1298130008.145277000
EOF
group_by_sample $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected


# The below is incremental samples of the data and timestamps:
# TS_diff    reads reads_mrg read_sectors ms_reading    writes write_mrg wrt_sectors ms_wrting  i ms_ding_io ms_weightd
# 1.14214000 1426         18        45568        561        47        94        2872        15  0        413        576
# 1.13886000 1602         22        51168        618       166        92       10328        51  1        468        667
# 1.14123000 1315         20        42016        511        52        86        2624        17  1        421        528
# 1.14904000 1451         10        46432        499        75       101        4576        19  0        409        518
# 1.14215000 1276         12        40800        433       161        90       11072        60  0        374        492


TEST_NAME="diskstats-005.txt"
cat <<EOF > $TMPDIR/expected
  #ts device    rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg
  1.0 {2}     2812.0    32.0    43.9     1%    0.6     0.4    92.7    61.1     2.8    67%    0.0     0.3  41%      0
  2.0 {2}     3160.1    31.9    49.3     1%    0.6     0.4   327.5    62.2     9.9    36%    0.1     0.3  46%      2
  3.0 {2}     2593.4    32.0    40.5     1%    0.5     0.4   102.6    50.5     2.5    62%    0.0     0.3  42%      2
  4.1 {2}     2859.4    32.0    44.7     1%    0.5     0.3   147.8    61.0     4.4    57%    0.0     0.3  40%      0
  5.1 {2}     2516.2    32.0    39.3     1%    0.4     0.3   317.5    68.8    10.7    36%    0.1     0.4  37%      0
EOF
group_by_sample samples/diskstats-005.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected


TEST_NAME="ts line"
cat <<EOF > $TMPDIR/expected
  #ts device    rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg
  1.0 {2}     2812.0    32.0    43.9     1%    0.6     0.4    92.7    61.1     2.8    67%    0.0     0.3  41%      0
  2.0 {2}     3160.1    31.9    49.3     1%    0.6     0.4   327.5    62.2     9.9    36%    0.1     0.3  46%      2
  3.0 {2}     2593.4    32.0    40.5     1%    0.5     0.4   102.6    50.5     2.5    62%    0.0     0.3  42%      2
  4.1 {2}     2859.4    32.0    44.7     1%    0.5     0.3   147.8    61.0     4.4    57%    0.0     0.3  40%      0
  5.1 {2}     2516.2    32.0    39.3     1%    0.4     0.3   317.5    68.8    10.7    36%    0.1     0.4  37%      0
EOF

cat > $TMPDIR/in <<EOF
TS 1298130002.073935000
EOF
cat samples/diskstats-005.txt >> $TMPDIR/in
group_by_sample $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
