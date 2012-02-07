#!/bin/bash

TESTS=4
TMPDIR=$TEST_TMPDIR

TEST_NAME="dmesg-001.txt"
cat <<EOF > $TMPDIR/expected
Fusion-MPT SAS
EOF
parse_raid_controller_dmesg samples/dmesg-001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="dmesg-002.txt"
cat <<EOF > $TMPDIR/expected
AACRAID
EOF
parse_raid_controller_dmesg samples/dmesg-002.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="dmesg-003.txt"
cat <<EOF > $TMPDIR/expected
LSI Logic MegaRAID SAS
EOF
parse_raid_controller_dmesg samples/dmesg-003.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="dmesg-004.txt"
cat <<EOF > $TMPDIR/expected
AACRAID
EOF
parse_raid_controller_dmesg samples/dmesg-004.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
