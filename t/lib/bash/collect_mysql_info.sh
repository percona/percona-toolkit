#!/usr/bin/env bash

plan 3

TMPDIR="$TEST_TMPDIR"
PATH="$PATH:$PERCONA_TOOLKIT_SANDBOX/bin"
TOOL="pt-mysql-summary"

. "$LIB_DIR/log_warn_die.sh"
. "$LIB_DIR/alt_cmds.sh"
. "$LIB_DIR/summary_common.sh"
. "$LIB_DIR/collect_mysql_info.sh"

# Prefix (with path) for the collect files.
local p="$TMPDIR/collect_mysql_info"

mkdir "$p"

parse_options "$BIN_DIR/pt-mysql-summary" --sleep 1 -- --defaults-file=/tmp/12345/my.sandbox.cnf

CMD_MYSQL="$(_which mysql)"
CMD_MYSQLDUMP="$(_which mysqldump)"

collect_mysql_info "$p" 1>/dev/null
wait

file_count=$(ls "$p" | wc -l)

is $file_count 12 "Creates the correct number of files (without --dump-schemas)"

grep -v grep "$p/percona-toolkit-mysqld-instances" | awk '{print $2}' > "$TMPDIR/collect_mysqld_instances1.test"
ps auxww 2>/dev/null | grep mysqld | grep -v grep | awk '{print $2}' > "$TMPDIR/collect_mysqld_instances2.test"

no_diff \
   "$TMPDIR/collect_mysqld_instances1.test" \
   "$TMPDIR/collect_mysqld_instances2.test" \
   "collect_mysql_info() finds the correct instances"

collect_mysqld_instances "$TMPDIR/collect_mysqld_instances3.test"

no_diff \
   "$TMPDIR/collect_mysqld_instances3.test" \
   "$TMPDIR/collect_mysqld_instances2.test" \
   "(sanity check) which are the same that collect_mysqld_instances() does"

$CMD_MYSQL $EXT_ARGV -ss -e 'SHOW /*!50000 GLOBAL*/ STATUS' > "$TMPDIR/collect_mysql_status"
no_diff \
   "$p/percona-toolkit-mysql-status" \
   "$TMPDIR/collect_mysql_status"    \
   "collect_mysql_info() finds the correct instances"

