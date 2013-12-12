# This program is copyright 2011-2012 Percona Inc.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.
# ###########################################################################
# collect_mysql_info package
# ###########################################################################

# Package: collect_mysql_info
# collect collects mysql information.

# XXX
# THIS LIB REQUIRES log_warn_die.sh, summary_common.sh, and alt_cmds.sh!
# XXX

CMD_MYSQL="${CMD_MYSQL:-""}"
CMD_MYSQLDUMP="${CMD_MYSQLDUMP:-""}"

# Simply looks for instances of mysqld in the outof of ps.
collect_mysqld_instances () {
   local variables_file="$1"

   local pids="$(_pidof mysqld)"

   if [ -n "$pids" ]; then

      for pid in $pids; do
         local nice="$( get_nice_of_pid $pid )"
         local oom="$( get_oom_of_pid $pid )"
         echo "internal::nice_of_$pid    $nice" >> "$variables_file"
         echo "internal::oom_of_$pid    $oom" >> "$variables_file"
      done

      pids="$(echo $pids | sed -e 's/ /,/g')"
      ps ww -p "$pids" 2>/dev/null
   else
      echo "mysqld doesn't appear to be running"
   fi

}

# Tries to find the my.cnf file by examining 'ps' output.
# You have to specify the port for the instance you are
# interested in, in case there are multiple instances.
find_my_cnf_file() {
   local file="$1"
   local port="${2:-""}"

   local cnf_file=""

   if [ "$port" ]; then
      # Find the cnf file for the specific port.
      cnf_file="$(grep --max-count 1 "/mysqld.*--port=$port" "$file" \
         | awk 'BEGIN{RS=" "; FS="=";} $1 ~ /--defaults-file/ { print $2; }')"
   else
      # Find the cnf file for the first mysqld instance.
      cnf_file="$(grep --max-count 1 '/mysqld' "$file" \
         | awk 'BEGIN{RS=" "; FS="=";} $1 ~ /--defaults-file/ { print $2; }')"
   fi

   if [ -z "$cnf_file" ]; then
      # Cannot autodetect config file, try common locations.
      if [ -e "/etc/my.cnf" ]; then
         cnf_file="/etc/my.cnf"
      elif [ -e "/etc/mysql/my.cnf" ]; then
         cnf_file="/etc/mysql/my.cnf"
      elif [ -e "/var/db/mysql/my.cnf" ]; then
         cnf_file="/var/db/mysql/my.cnf";
      fi
   fi

   echo "$cnf_file"
}

collect_mysql_variables () {
   $CMD_MYSQL $EXT_ARGV -ss  -e 'SHOW /*!40100 GLOBAL*/ VARIABLES'
}

collect_mysql_status () {
   $CMD_MYSQL $EXT_ARGV -ss -e 'SHOW /*!50000 GLOBAL*/ STATUS'
}

collect_mysql_databases () {
   $CMD_MYSQL $EXT_ARGV -ss -e 'SHOW DATABASES' 2>/dev/null
}

collect_mysql_plugins () {
   $CMD_MYSQL $EXT_ARGV -ss -e 'SHOW PLUGINS' 2>/dev/null
}

collect_mysql_slave_status () {
   $CMD_MYSQL $EXT_ARGV -ssE -e 'SHOW SLAVE STATUS' 2>/dev/null
}

collect_mysql_innodb_status () {
   $CMD_MYSQL $EXT_ARGV -ssE -e 'SHOW /*!50000 ENGINE*/ INNODB STATUS' 2>/dev/null
}

collect_mysql_processlist () {
   $CMD_MYSQL $EXT_ARGV -ssE -e 'SHOW FULL PROCESSLIST' 2>/dev/null
}

collect_mysql_users () {
   $CMD_MYSQL $EXT_ARGV -ss -e 'SELECT COUNT(*), SUM(user=""), SUM(password=""), SUM(password NOT LIKE "*%") FROM mysql.user' 2>/dev/null
}

collect_master_logs_status () {
   local master_logs_file="$1"
   local master_status_file="$2"
   $CMD_MYSQL $EXT_ARGV -ss -e 'SHOW MASTER LOGS' > "$master_logs_file" 2>/dev/null
   $CMD_MYSQL $EXT_ARGV -ss -e 'SHOW MASTER STATUS' > "$master_status_file" 2>/dev/null
}

# Somewhat different from the others, this one joins the status we got earlier
collect_mysql_deferred_status () {
   local status_file="$1"
   collect_mysql_status > "$PT_TMPDIR/defer_gatherer"
   join "$status_file" "$PT_TMPDIR/defer_gatherer"
}

collect_internal_vars () {
   local mysqld_executables="${1:-""}"

   local FNV_64=""
   if $CMD_MYSQL $EXT_ARGV -e 'SELECT FNV_64("a")' >/dev/null 2>&1; then
      FNV_64="Enabled";
   else
      FNV_64="Unknown";
   fi

   local now="$($CMD_MYSQL $EXT_ARGV -ss -e 'SELECT NOW()')"
   local user="$($CMD_MYSQL $EXT_ARGV -ss -e 'SELECT CURRENT_USER()')"
   local trigger_count=$($CMD_MYSQL $EXT_ARGV -ss -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TRIGGERS" 2>/dev/null)

   echo "pt-summary-internal-mysql_executable    $CMD_MYSQL"
   echo "pt-summary-internal-now    $now"
   echo "pt-summary-internal-user   $user"
   echo "pt-summary-internal-FNV_64   $FNV_64"
   echo "pt-summary-internal-trigger_count   $trigger_count"

   if [ -e "$mysqld_executables" ]; then
      local i=1
      while read executable; do
         echo "pt-summary-internal-mysqld_executable_${i}   $(has_symbols "$executable")"
         i=$(($i + 1))
      done < "$mysqld_executables"
   fi
}

# Uses mysqldump and dumps the results to FILE.
# args and dbtodump are passed to mysqldump.
get_mysqldump_for () {
   local args="$1"
   local dbtodump="${2:-"--all-databases"}"

   $CMD_MYSQLDUMP $EXT_ARGV --no-data --skip-comments \
      --skip-add-locks --skip-add-drop-table --compact \
      --skip-lock-all-tables --skip-lock-tables --skip-set-charset \
      ${args} --databases $(local IFS=,; echo ${dbtodump})
}

# Returns a string with arguments to pass to mysqldump.
# Takes one argument, which should be a
get_mysqldump_args () {
   local file="$1"
   local trg_arg=""

   # If mysqldump supports triggers, then add options for routines.
   if $CMD_MYSQLDUMP --help --verbose 2>&1 | grep triggers >/dev/null; then
      # "mysqldump supports triggers"
      trg_arg="--routines"
   fi

   if [ "${trg_arg}" ]; then
      # Find out if there are any triggers.  If there are none, we will skip
      # that option to mysqldump, because when mysqldump checks for them, it
      # can take a long time, one table at a time.
      local triggers="--skip-triggers"
      local trg=$(get_var "pt-summary-internal-trigger_count" "$file" )
      if [ -n "${trg}" ] && [ "${trg}" -gt 0 ]; then
         triggers="--triggers"
      fi
      trg_arg="${trg_arg} ${triggers}";
   fi
   echo "${trg_arg}"
}

collect_mysqld_executables () {
   local mysqld_instances="$1"

   local ps_opt="cmd="
   if [ "$(uname -s)" = "Darwin" ]; then
      ps_opt="command="
   fi

   for pid in $( grep '/mysqld' "$mysqld_instances" | awk '/^.*[0-9]/{print $1}' ); do
      ps -o $ps_opt -p $pid | sed -e 's/^\(.*mysqld\) .*/\1/'
   done | sort -u
}

collect_mysql_info () {
   local dir="$1"

   collect_mysql_variables     > "$dir/mysql-variables"
   collect_mysql_status        > "$dir/mysql-status"
   collect_mysql_databases     > "$dir/mysql-databases"
   collect_mysql_plugins       > "$dir/mysql-plugins"
   collect_mysql_slave_status  > "$dir/mysql-slave"
   collect_mysql_innodb_status > "$dir/innodb-status"
   collect_mysql_processlist   > "$dir/mysql-processlist"   
   collect_mysql_users         > "$dir/mysql-users"

   collect_mysqld_instances   "$dir/mysql-variables"  > "$dir/mysqld-instances"
   collect_mysqld_executables "$dir/mysqld-instances" > "$dir/mysqld-executables"

   local binlog="$(get_var log_bin "$dir/mysql-variables")"
   if [ "${binlog}" ]; then
      # "Got a binlog, going to get MASTER LOGS and MASTER STATUS"
      collect_master_logs_status "$dir/mysql-master-logs" "$dir/mysql-master-status"
   fi

   local uptime="$(get_var Uptime "$dir/mysql-status")"
   local current_time="$($CMD_MYSQL $EXT_ARGV -ss -e \
                         "SELECT LEFT(NOW() - INTERVAL ${uptime} SECOND, 16)")"

   local port="$(get_var port "$dir/mysql-variables")"
   local cnf_file="$(find_my_cnf_file "$dir/mysqld-instances" ${port})"

   [ -e "$cnf_file" ] && cat "$cnf_file" > "$dir/mysql-config-file"

   local pid_file="$(get_var "pid_file" "$dir/mysql-variables")"
   local pid_file_exists=""
   [ -e "${pid_file}" ] && pid_file_exists=1
   echo "pt-summary-internal-pid_file_exists    $pid_file_exists" >> "$dir/mysql-variables"

   # TODO: Do these require a file of their own?
   echo "pt-summary-internal-current_time    $current_time" >> "$dir/mysql-variables"
   echo "pt-summary-internal-Config_File_path    $cnf_file" >> "$dir/mysql-variables"
   collect_internal_vars "$dir/mysqld-executables" >> "$dir/mysql-variables"

   # mysqldump schemas
   if [ "$OPT_DATABASES" -o "$OPT_ALL_DATABASES" ]; then
      local trg_arg="$(get_mysqldump_args "$dir/mysql-variables")"
      local dbs="${OPT_DATABASES:-""}"
      get_mysqldump_for "${trg_arg}" "$dbs" > "$dir/mysqldump"
   fi

   # TODO: gather this data in the same format as normal: TS line, stats
   (
      sleep $OPT_SLEEP
      collect_mysql_deferred_status "$dir/mysql-status" > "$dir/mysql-status-defer"
   ) &
   _d "Forked child is $!"
}

# ###########################################################################
# End collect_mysql_info package
# ###########################################################################
