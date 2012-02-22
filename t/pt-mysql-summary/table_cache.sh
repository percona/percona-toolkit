#!/bin/bash

TEST=3
TMPDIR=$TEST_TMPDIR

touch $TMPDIR/table_cache_tests

is                                                  \
   $(get_table_cache "$TMPDIR/table_cache_tests")   \
   0                                                \
   "0 if neither table_cache nor table_open_cache are present"

cat <<EOF > $TMPDIR/table_cache_tests
table_cache       5
table_open_cache  4
EOF

is                                                 \
   $(get_table_cache "$TMPDIR/table_cache_tests")  \
   4                                               \
   "If there's a table_open_cache present, uses that"

cat <<EOF > $TMPDIR/table_cache_tests
table_cache       5
EOF

is                                                 \
   $(get_table_cache "$TMPDIR/table_cache_tests")  \
   5                                               \
   "Otherwise, defaults to table_cache"
