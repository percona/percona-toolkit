#!/bin/bash

TESTS=5
TMPDIR=$TEST_TMPDIR

TEST_NAME="lspci-001.txt"
cat <<EOF > $TMPDIR/expected
Fusion-MPT SAS
EOF
parse_raid_controller_lspci samples/lspci-001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="lspci-002.txt"
cat <<EOF > $TMPDIR/expected
LSI Logic Unknown
EOF
parse_raid_controller_lspci samples/lspci-002.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="lspci-003.txt"
cat <<EOF > $TMPDIR/expected
AACRAID
EOF
parse_raid_controller_lspci samples/lspci-003.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="lspci-004.txt"
cat <<EOF > $TMPDIR/expected
LSI Logic MegaRAID SAS
EOF
parse_raid_controller_lspci samples/lspci-004.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="lspci-006.txt"
cat <<EOF > $TMPDIR/expected
HP Smart Array
EOF
parse_raid_controller_lspci samples/lspci-006.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
