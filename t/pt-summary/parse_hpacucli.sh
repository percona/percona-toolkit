#!/bin/bash

TESTS=1
TMPDIR=$TEST_TMPDIR

cat <<EOF > $TMPDIR/expected
      logicaldrive 1 (136.7 GB, RAID 1, OK)
      physicaldrive 1I:1:1 (port 1I:box 1:bay 1, SAS, 146 GB, OK)
      physicaldrive 1I:1:2 (port 1I:box 1:bay 2, SAS, 146 GB, OK)
EOF

cat <<EOF > $TMPDIR/in

Smart Array P400i in Slot 0 (Embedded)    (sn: PH73MU7325     )

   array A (SAS, Unused Space: 0 MB)


      logicaldrive 1 (136.7 GB, RAID 1, OK)

      physicaldrive 1I:1:1 (port 1I:box 1:bay 1, SAS, 146 GB, OK)
      physicaldrive 1I:1:2 (port 1I:box 1:bay 2, SAS, 146 GB, OK)

EOF
parse_hpacucli $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
