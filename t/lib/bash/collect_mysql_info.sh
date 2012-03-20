#!/usr/bin/env bash

plan 15

TMPDIR="$TEST_TMPDIR"
PATH="$PATH:$PERCONA_TOOLKIT_SANDBOX/bin"
TOOL="pt-mysql-summary"

. "$LIB_DIR/log_warn_die.sh"
. "$LIB_DIR/alt_cmds.sh"
. "$LIB_DIR/parse_options.sh"
. "$LIB_DIR/summary_common.sh"
. "$LIB_DIR/collect_mysql_info.sh"

# Prefix (with path) for the collect files.
p="$TMPDIR/collect_mysql_info"
samples="$PERCONA_TOOLKIT_BRANCH/t/pt-mysql-summary/samples"

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

grep -v grep "$TMPDIR/collect_mysqld_instances3.test" | awk '{print $2}' > "$TMPDIR/collect_mysqld_instances4.test"

no_diff \
   "$TMPDIR/collect_mysqld_instances4.test" \
   "$TMPDIR/collect_mysqld_instances2.test" \
   "(sanity check) which are the same that collect_mysqld_instances() does"

# collect_mysql_status
$CMD_MYSQL $EXT_ARGV -ss -e 'SHOW /*!50000 GLOBAL*/ STATUS' > "$TMPDIR/collect_mysql_status"

pat='Com_\|Bytes_\|Handler_\|Created_\|Que\|Uptime\|Select_scan\|Connections\|Opened_files\|_created\|Table_locks'
grep -v $pat "$p/percona-toolkit-mysql-status" > "$TMPDIR/collect_mysql_status_collect"
grep -v $pat "$TMPDIR/collect_mysql_status" > "$TMPDIR/collect_mysql_status_manual"

no_diff \
   "$TMPDIR/collect_mysql_status_collect" \
   "$TMPDIR/collect_mysql_status_manual"    \
   "collect_mysql_status works the same than if done manually"

port="$(get_var port "$p/percona-toolkit-mysql-variables")"

is \
   $port \
   12345 \
   "Finds the correct port"

# collect_internal_vars
pat='pt-summary-internal-user\|pt-summary-internal-FNV_64\|pt-summary-internal-trigger_count\|pt-summary-internal-symbols'

collect_internal_vars "$TMPDIR/collect_internal_vars"
is \
   "$( grep $pat "$p/percona-toolkit-mysql-variables" )" \
   "$( grep $pat "$TMPDIR/collect_internal_vars" )" \
   "collect_internal_vars works"

# find_my_cnf_file
cnf_file=$(find_my_cnf_file "$p/percona-toolkit-mysqld-instances" ${port});

is \
   "$cnf_file" \
   "/tmp/12345/my.sandbox.cnf" \
   "find_my_cnf_file gets the correct file"

res=$(find_my_cnf_file "$samples/ps-mysqld-001.txt")
is "$res" "/tmp/12345/my.sandbox.cnf" "ps-mysqld-001.txt"

res=$(find_my_cnf_file "$samples/ps-mysqld-001.txt" 12346)
is "$res" "/tmp/12346/my.sandbox.cnf" "ps-mysqld-001.txt with port"

res=$(find_my_cnf_file "$samples/ps-mysqld-004.txt")
is "$res" "/var/lib/mysql/my.cnf" "ps-mysqld-004.txt"

res=$(find_my_cnf_file "$samples/ps-mysqld-004.txt" 12345)
is "$res" "/var/lib/mysql/my.cnf" "ps-mysqld-004.txt with port"


# collect_mysql_databases
$CMD_MYSQL $EXT_ARGV -ss -e 'SHOW DATABASES' > "$TMPDIR/mysql_collect_databases" 2>/dev/null

no_diff \
   "$p/percona-toolkit-mysql-databases" \
   "$TMPDIR/mysql_collect_databases"       \
   "collect_mysql_databases works"

$CMD_MYSQL $EXT_ARGV -ss -e 'CREATE DATABASE collect_mysql_databases_test;' 1>/dev/null 2>&1

collect_mysql_databases "$TMPDIR/mysql_collect_databases"

$CMD_MYSQL $EXT_ARGV -ss -e 'DROP DATABASE collect_mysql_databases_test;'

cmd_ok \
   "grep collect_mysql_databases_test '$TMPDIR/mysql_collect_databases' 1>/dev/null 2>&1" \
   "...and finds new dbs when we add them"

# collect_master_logs_status

if [ -n "$(get_var log_bin "$p/percona-toolkit-mysql-variables")" ]; then
   cmd_ok \
      "test -e $p/percona-toolkit-mysql-master-logs" \
      "If we have a binlog, a file with the master logs should exist"
   cmd_ok \
      "test -e $p/percona-toolkit-mysql-master-status" \
      "And likewise for master status"
else
   skip 1 2 "no binlog"
fi
