#!/bin/bash

TESTS=1
TMPDIR=$TEST_TMPDIR

cat <<EOF > $TMPDIR/expected
                  Binlogs | 20
               Zero-Sized | 3
               Total Size | 6.5G
EOF

summarize_binlogs samples/mysql-master-logs-001.txt > $TMPDIR/got
no_diff $TMPDIR/expected $TMPDIR/got
