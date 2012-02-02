#!/bin/bash

TESTS=1
TMPDIR=$TEST_TMPDIR

cat <<EOF > $TMPDIR/expected
Xen
EOF
parse_virtualization_dmesg samples/dmesg-006.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
