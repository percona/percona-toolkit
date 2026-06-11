#!/bin/bash

TEST=1

cat <<EOF > $TMPDIR/expected
        binlog_do_db | foo
    binlog_ignore_db | mysql,test
EOF

format_binlog_filters samples/mysql-show-master-status-001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
