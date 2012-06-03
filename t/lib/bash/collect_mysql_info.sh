#!/usr/bin/env bash

plan 20

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

is $file_count 14 "Creates the correct number of files (without --databases)"

awk '{print $1}' "$p/mysqld-instances" > "$TMPDIR/collect_mysqld_instances1.test"
ps ww -p "$(_pidof mysqld | sed -e "s/ /,/g")" | awk '{print $1}' > "$TMPDIR/collect_mysqld_instances2.test"

no_diff \
   "$TMPDIR/collect_mysqld_instances1.test" \
   "$TMPDIR/collect_mysqld_instances2.test" \
   "collect_mysql_info() finds the correct instances"

collect_mysqld_instances /dev/null > "$TMPDIR/collect_mysqld_instances3.test"

awk '{print $1}' "$TMPDIR/collect_mysqld_instances3.test"> "$TMPDIR/collect_mysqld_instances4.test"

no_diff \
   "$TMPDIR/collect_mysqld_instances4.test" \
   "$TMPDIR/collect_mysqld_instances2.test" \
   "(sanity check) which are the same that collect_mysqld_instances() does"

# collect_mysql_status
$CMD_MYSQL $EXT_ARGV -ss -e 'SHOW /*!50000 GLOBAL*/ STATUS' > "$TMPDIR/collect_mysql_status"


# TODO This is still pretty fragile.
awk '{print $1}' "$p/mysql-status" | sort > "$TMPDIR/collect_mysql_status_collect"
awk '{print $1}' "$TMPDIR/collect_mysql_status" | sort  > "$TMPDIR/collect_mysql_status_manual"

no_diff \
   "$TMPDIR/collect_mysql_status_collect" \
   "$TMPDIR/collect_mysql_status_manual"    \
   "collect_mysql_status works the same than if done manually"

port="$(get_var port "$p/mysql-variables")"

is \
   $port \
   12345 \
   "Finds the correct port"

# collect_internal_vars
pat='pt-summary-internal-user\|pt-summary-internal-FNV_64\|pt-summary-internal-trigger_count\|pt-summary-internal-symbols'

collect_internal_vars > "$TMPDIR/collect_internal_vars"
is \
   "$( grep $pat "$p/mysql-variables" )" \
   "$( grep $pat "$TMPDIR/collect_internal_vars" )" \
   "collect_internal_vars works"

# find_my_cnf_file
cnf_file=$(find_my_cnf_file "$p/mysqld-instances" ${port});

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
   "$p/mysql-databases" \
   "$TMPDIR/mysql_collect_databases"       \
   "collect_mysql_databases works"

$CMD_MYSQL $EXT_ARGV -ss -e 'CREATE DATABASE collect_mysql_databases_test;' 1>/dev/null 2>&1

collect_mysql_databases > "$TMPDIR/mysql_collect_databases"

$CMD_MYSQL $EXT_ARGV -ss -e 'DROP DATABASE collect_mysql_databases_test;'

cmd_ok \
   "grep collect_mysql_databases_test '$TMPDIR/mysql_collect_databases' 1>/dev/null 2>&1" \
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

   printf '#!/usr/bin/env bash\necho $@\n' > "$TMPDIR/mysqldump_fake.sh"
   chmod +x "$TMPDIR/mysqldump_fake.sh"
   local orig_mysqldump="$CMD_MYSQLDUMP"
   local CMD_MYSQLDUMP="$TMPDIR/mysqldump_fake.sh"

   cat <<EOF > "$TMPDIR/expected"
--defaults-file=/tmp/12345/my.sandbox.cnf --no-data --skip-comments --skip-add-locks --skip-add-drop-table --compact --skip-lock-all-tables --skip-lock-tables --skip-set-charset --databases --all-databases
EOF
   get_mysqldump_for '' > "$dir/mysqldump_test_1"
   no_diff \
      "$dir/mysqldump_test_1" \
      "$TMPDIR/expected" \
      "get_mysqldump_for picks a name default"

   get_mysqldump_for '' '--all-databases' > "$dir/mysqldump_test_2"
   no_diff \
      "$dir/mysqldump_test_2" \
      "$TMPDIR/expected" \
      "..which is the same as if we explicitly set --all-databases"

   cat <<EOF > "$TMPDIR/expected"
--defaults-file=/tmp/12345/my.sandbox.cnf --no-data --skip-comments --skip-add-locks --skip-add-drop-table --compact --skip-lock-all-tables --skip-lock-tables --skip-set-charset --databases a
EOF
   get_mysqldump_for '' 'a' > "$dir/mysqldump_test_3"
   no_diff \
      "$dir/mysqldump_test_3" \
      "$TMPDIR/expected" \
      "get_mysqldump_for: Explicitly setting a database works"

   cat <<EOF > "$TMPDIR/expected"
--defaults-file=/tmp/12345/my.sandbox.cnf --no-data --skip-comments --skip-add-locks --skip-add-drop-table --compact --skip-lock-all-tables --skip-lock-tables --skip-set-charset --databases a b
EOF
   get_mysqldump_for '' 'a,b' > "$dir/mysqldump_test_4"
   no_diff \
      "$dir/mysqldump_test_4" \
      "$TMPDIR/expected" \
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

mkdir "$TMPDIR/mysqldump"
test_get_mysqldump_for "$TMPDIR/mysqldump"
