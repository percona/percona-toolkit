#!/bin/bash

TESTS=3
TMPDIR=$TEST_TMPDIR

TEST_NAME="get_mysql_timezone"
cp samples/mysql-variables-001.txt $TMPDIR/percona-toolkit-mysql-variables
is $(get_mysql_timezone "$TMPDIR/percona-toolkit-mysql-variables") "EDT"

TEST_NAME="get_mysql_uptime"
cat <<EOF > $TMPDIR/expected
2010-05-27 11:38 (up 0+02:08:52)
EOF
cp samples/mysql-status-001.txt $TMPDIR/percona-toolkit-mysql-status
local uptime="$(get_stat Uptime $TMPDIR/percona-toolkit-mysql-status)"
local current_time="$(echo -e "2010-05-27 11:38\n")"
get_mysql_uptime "${uptime}" "${current_time}" > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="get_mysql_version"
cat <<EOF > $TMPDIR/expected
             Version | 5.0.51a-24+lenny2 (Debian)
            Built On | debian-linux-gnu i486
EOF
cp samples/mysql-variables-001.txt $TMPDIR/percona-toolkit-mysql-variables
get_mysql_version $TMPDIR/percona-toolkit-mysql-variables > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
