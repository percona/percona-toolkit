#!/usr/bin/env bash

plan 24

PT_TMPDIR="$TEST_PT_TMPDIR"
PATH="$PATH:$PERCONA_TOOLKIT_SANDBOX/bin"
TOOL="pt-mysql-summary"

. "$LIB_DIR/log_warn_die.sh"
. "$LIB_DIR/alt_cmds.sh"
. "$LIB_DIR/parse_options.sh"
. "$LIB_DIR/summary_common.sh"
. "$LIB_DIR/collect_mysql_info.sh"

# Prefix (with path) for the collect files.
p="$PT_TMPDIR/collect_mysql_info"
samples="$PERCONA_TOOLKIT_BRANCH/t/pt-mysql-summary/samples"

mkdir "$p"

# This is mostly for the find_my_cnf_file tests.
# Test machines may have one of these, and find_my_cnf_file will use
# the same if the specific port-based cnf file isn't found.
if [ -e "/etc/my.cnf" ]; then
   sys_cnf_file="/etc/my.cnf"
elif [ -e "/etc/mysql/my.cnf" ]; then
   sys_cnf_file="/etc/mysql/my.cnf"
elif [ -e "/var/db/mysql/my.cnf" ]; then
   sys_cnf_file="/var/db/mysql/my.cnf";
else
   sys_cnf_file=""
fi

parse_options "$BIN_DIR/pt-mysql-summary" --sleep 1 -- --defaults-file=/tmp/12345/my.sandbox.cnf

CMD_MYSQL="$(_which mysql)"
CMD_MYSQLDUMP="$(_which mysqldump)"

collect_mysql_info "$p" 1>/dev/null
wait

file_count=$(ls "$p" | wc -l)

if [ "$sys_cnf_file" ]; then
   n_files=14
else
   n_files=13
fi

is $file_count $n_files "Creates the correct number of files (without --databases)"

awk '{print $1}' "$p/mysqld-instances" > "$PT_TMPDIR/collect_mysqld_instances1.test"
pids="$(_pidof mysqld)"
pids="$(echo $pids | sed -e "s/[ \n]/,/g")"
ps ww -p "$pids" | awk '{print $1}' > "$PT_TMPDIR/collect_mysqld_instances2.test"

no_diff \
   "$PT_TMPDIR/collect_mysqld_instances1.test" \
   "$PT_TMPDIR/collect_mysqld_instances2.test" \
   "collect_mysql_info() finds the correct instances"

collect_mysqld_instances /dev/null > "$PT_TMPDIR/collect_mysqld_instances3.test"

awk '{print $1}' "$PT_TMPDIR/collect_mysqld_instances3.test"> "$PT_TMPDIR/collect_mysqld_instances4.test"

no_diff \
   "$PT_TMPDIR/collect_mysqld_instances4.test" \
   "$PT_TMPDIR/collect_mysqld_instances2.test" \
   "(sanity check) which are the same that collect_mysqld_instances() does"

# collect_mysql_status
$CMD_MYSQL $EXT_ARGV -ss -e 'SHOW /*!50000 GLOBAL*/ STATUS' > "$PT_TMPDIR/collect_mysql_status"


# TODO This is still pretty fragile.
awk '{print $1}' "$p/mysql-status" | sort > "$PT_TMPDIR/collect_mysql_status_collect"
awk '{print $1}' "$PT_TMPDIR/collect_mysql_status" | sort  > "$PT_TMPDIR/collect_mysql_status_manual"

no_diff \
   "$PT_TMPDIR/collect_mysql_status_collect" \
   "$PT_TMPDIR/collect_mysql_status_manual"    \
   "collect_mysql_status works the same than if done manually"

port="$(get_var port "$p/mysql-variables")"

is \
   $port \
   12345 \
   "Finds the correct port"

# collect_internal_vars
pat='pt-summary-internal-user\|pt-summary-internal-FNV_64\|pt-summary-internal-trigger_count\|pt-summary-internal-symbols'

collect_internal_vars > "$PT_TMPDIR/collect_internal_vars"
is \
   "$( grep $pat "$p/mysql-variables" )" \
   "$( grep $pat "$PT_TMPDIR/collect_internal_vars" )" \
   "collect_internal_vars works"

# find_my_cnf_file

# We know the port is 12345 (2nd to last test), but the sandbox is started
# with just --defaults-file, no --port, so find_my_cnf_file isn't going to
# be able to get the specific cnf file.
cnf_file=$(find_my_cnf_file "$p/mysqld-instances" ${port});

is "$cnf_file" "$sys_cnf_file" "find_my_cnf_file gets the correct file"
[ $? -ne 0 ] && diag "$p/mysqld-instances"

# ps-mysqld-001.txt has several instances:
# port 3306  cnf -
# port 12345 cnf /tmp/12345/my.sandbox.cnf
# port 12346 cnf /tmp/12346/my.sandbox.cnf

res=$(find_my_cnf_file "$samples/ps-mysqld-001.txt")
is "$res" "$sys_cnf_file" "ps-mysqld-001.txt no port"

res=$(find_my_cnf_file "$samples/ps-mysqld-001.txt" 3306)
is "$res" "$sys_cnf_file" "ps-mysqld-001.txt port but no cnf"

res=$(find_my_cnf_file "$samples/ps-mysqld-001.txt" 999)
is "$res" "$sys_cnf_file" "ps-mysqld-001.txt nonexistent port"

res=$(find_my_cnf_file "$samples/ps-mysqld-001.txt" 12346)
is "$res" "/tmp/12346/my.sandbox.cnf" "ps-mysqld-001.txt port 12346"

res=$(find_my_cnf_file "$samples/ps-mysqld-001.txt" 12345)
is "$res" "/tmp/12345/my.sandbox.cnf" "ps-mysqld-001.txt port 12345"

# ps-mysqld-004.txt has 1 instance without --port using
# --defaults-file=/var/lib/mysql/my.cnf

res=$(find_my_cnf_file "$samples/ps-mysqld-004.txt")
is "$res" "/var/lib/mysql/my.cnf" "ps-mysqld-004.txt no port"

res=$(find_my_cnf_file "$samples/ps-mysqld-004.txt" 12345)
is "$res" "$sys_cnf_file" "ps-mysqld-004.txt port 12345"

# ps-mysqld-005.txt has the 3 sandbox instances, but 12347
# is first, which was causing bug 1070916.

res=$(find_my_cnf_file "$samples/ps-mysqld-005.txt" 12345)
is "$res" "$sys_cnf_file" "ps-mysqld-005.txt port 12345 (bug 1070916)"

# collect_mysql_databases
$CMD_MYSQL $EXT_ARGV -ss -e 'SHOW DATABASES' > "$PT_TMPDIR/mysql_collect_databases" 2>/dev/null

no_diff \
   "$p/mysql-databases" \
   "$PT_TMPDIR/mysql_collect_databases"       \
   "collect_mysql_databases works"

$CMD_MYSQL $EXT_ARGV -ss -e 'CREATE DATABASE collect_mysql_databases_test;' 1>/dev/null 2>&1

collect_mysql_databases > "$PT_TMPDIR/mysql_collect_databases"

$CMD_MYSQL $EXT_ARGV -ss -e 'DROP DATABASE collect_mysql_databases_test;'

cmd_ok \
   "grep collect_mysql_databases_test '$PT_TMPDIR/mysql_collect_databases' 1>/dev/null 2>&1" \
   "...and finds new dbs when we add them"

# collect_master_logs_status

if [ -n "$(get_var log_bin "$p/mysql-variables")" ]; then
   cmd_ok \
      "test -e $p/mysql-master-logs" \
      "If we have a binlog, a file with the master logs should exist"
   cmd_ok \
      "test -e $p/mysql-master-status" \
      "And likewise for master status"
else
   skip 1 2 "no binlog"
fi

# get_mysqldump_for

test_get_mysqldump_for () {
   local dir="$1"
   # Let's fake mysqldump

   printf '#!/usr/bin/env bash\necho $@\n' > "$PT_TMPDIR/mysqldump_fake.sh"
   chmod +x "$PT_TMPDIR/mysqldump_fake.sh"
   local orig_mysqldump="$CMD_MYSQLDUMP"
   local CMD_MYSQLDUMP="$PT_TMPDIR/mysqldump_fake.sh"

   cat <<EOF > "$PT_TMPDIR/expected"
--defaults-file=/tmp/12345/my.sandbox.cnf --no-data --skip-comments --skip-add-locks --skip-add-drop-table --compact --skip-lock-all-tables --skip-lock-tables --skip-set-charset --databases --all-databases
EOF
   get_mysqldump_for '' > "$dir/mysqldump_test_1"
   no_diff \
      "$dir/mysqldump_test_1" \
      "$PT_TMPDIR/expected" \
      "get_mysqldump_for picks a name default"

   get_mysqldump_for '' '--all-databases' > "$dir/mysqldump_test_2"
   no_diff \
      "$dir/mysqldump_test_2" \
      "$PT_TMPDIR/expected" \
      "..which is the same as if we explicitly set --all-databases"

   cat <<EOF > "$PT_TMPDIR/expected"
--defaults-file=/tmp/12345/my.sandbox.cnf --no-data --skip-comments --skip-add-locks --skip-add-drop-table --compact --skip-lock-all-tables --skip-lock-tables --skip-set-charset --databases a
EOF
   get_mysqldump_for '' 'a' > "$dir/mysqldump_test_3"
   no_diff \
      "$dir/mysqldump_test_3" \
      "$PT_TMPDIR/expected" \
      "get_mysqldump_for: Explicitly setting a database works"

   cat <<EOF > "$PT_TMPDIR/expected"
--defaults-file=/tmp/12345/my.sandbox.cnf --no-data --skip-comments --skip-add-locks --skip-add-drop-table --compact --skip-lock-all-tables --skip-lock-tables --skip-set-charset --databases a b
EOF
   get_mysqldump_for '' 'a,b' > "$dir/mysqldump_test_4"
   no_diff \
      "$dir/mysqldump_test_4" \
      "$PT_TMPDIR/expected" \
      "get_mysqldump_for: Two databases separated by a comma are interpreted correctly"

   if [ -n "$orig_mysqldump" ]; then
      local CMD_MYSQLDUMP="$orig_mysqldump"
      $CMD_MYSQL $EXT_ARGV -ss -e 'CREATE DATABASE collect_mysql_databases_test1;' 1>/dev/null 2>&1
      $CMD_MYSQL $EXT_ARGV -ss -e 'CREATE DATABASE collect_mysql_databases_test2;' 1>/dev/null 2>&1

      get_mysqldump_for '' "collect_mysql_databases_test1,collect_mysql_databases_test2" > "$dir/mysqldump_test_5"

      like \
         "$(cat $dir/mysqldump_test_5)" \
         'use `collect_mysql_databases_test1`.*use `collect_mysql_databases_test2`|use `collect_mysql_databases_test2`.*use `collect_mysql_databases_test1`' \
         "get_mysqldump_for dumps the dbs we request"

      $CMD_MYSQL $EXT_ARGV -ss -e 'DROP DATABASE collect_mysql_databases_test1;'
      $CMD_MYSQL $EXT_ARGV -ss -e 'DROP DATABASE collect_mysql_databases_test2;'
      
   else
      skip 1 1 "No mysqldump"
   fi

}

mkdir "$PT_TMPDIR/mysqldump"
test_get_mysqldump_for "$PT_TMPDIR/mysqldump"
