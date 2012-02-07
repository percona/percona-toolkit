#!/bin/bash

TESTS=2
TMPDIR=$TEST_TMPDIR

TEST_NAME="ip-s-link-001.txt"
cat <<EOF > $TMPDIR/expected
  interface  rx_bytes rx_packets  rx_errors   tx_bytes tx_packets  tx_errors
  ========= ========= ========== ========== ========== ========== ==========
  lo          3000000      25000          0    3000000      25000          0
  eth0      175000000   30000000          0  125000000     900000          0
  wlan0      50000000      80000          0   20000000      90000          0
  vboxnet0          0          0          0          0          0          0
EOF
parse_ip_s_link samples/ip-s-link-001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="ip-s-link-002.txt"
cat <<EOF > $TMPDIR/expected
  interface  rx_bytes rx_packets  rx_errors   tx_bytes tx_packets  tx_errors
  ========= ========= ========== ========== ========== ========== ==========
  lo       3500000000  350000000          0 3500000000  350000000          0
  eth0     1750000000 1250000000          0 3500000000  700000000          0
  eth1     1250000000   60000000          0  900000000   50000000          0
  sit0              0          0          0          0          0          0
EOF
parse_ip_s_link samples/ip-s-link-002.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
