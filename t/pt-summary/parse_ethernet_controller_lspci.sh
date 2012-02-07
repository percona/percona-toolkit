#!/bin/bash

TESTS=1
TMPDIR=$TEST_TMPDIR

cat <<EOF > $TMPDIR/expected
  Controller | Broadcom Corporation NetXtreme II BCM5708 Gigabit Ethernet (rev 12)
  Controller | Broadcom Corporation NetXtreme II BCM5708 Gigabit Ethernet (rev 12)
EOF
parse_ethernet_controller_lspci samples/lspci-001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
