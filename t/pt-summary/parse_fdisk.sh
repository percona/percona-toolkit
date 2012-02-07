#!/bin/bash

TESTS=1
TMPDIR=$TEST_TMPDIR

cat <<EOF > $TMPDIR/expected
Device       Type      Start        End               Size
============ ==== ========== ========== ==================
/dev/dm-0    Disk                             494609104896
/dev/dm-1    Disk                               5284823040
/dev/sda     Disk                             500107862016
/dev/sda1    Part          1         26          205632000
/dev/sda2    Part         26      60801       499891392000
EOF
parse_fdisk samples/fdisk-01.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
