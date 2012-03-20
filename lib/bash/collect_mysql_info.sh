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

# Simply looks for instances of mysqld in the outof of ps.
collect_mysqld_instances () {
   local file="$1"
   ps auxww 2>/dev/null | grep mysqld > "$file"
}

# Tries to find the my.cnf file by examining 'ps' output.
# You have to specify the port for the instance you are
# interested in, in case there are multiple instances.
find_my_cnf_file() {
   local file="$1"
   local port=${2:-""}

   local cnf_file=""
   if test -n "$port" && grep -- "/mysqld.*--port=$port" "${file}" >/dev/null 2>&1 ; then
      cnf_file="$(grep -- "/mysqld.*--port=$port" "${file}" \
         | awk 'BEGIN{RS=" "; FS="=";} $1 ~ /--defaults-file/ { print $2; }' \
         | head -n1)"
   else
      cnf_file="$(grep '/mysqld' "${file}" \
         | awk 'BEGIN{RS=" "; FS="=";} $1 ~ /--defaults-file/ { print $2; }' \
         | head -n1)"
   fi

   if [ ! -n "${cnf_file}" ]; then
      _d "Cannot autodetect config file, trying common locations"
      cnf_file="/etc/my.cnf";
      if [ ! -e "${cnf_file}" ]; then
         cnf_file="/etc/mysql/my.cnf";
      fi
      if [ ! -e "${cnf_file}" ]; then
         cnf_file="/var/db/mysql/my.cnf";
      fi
   fi

   echo "$cnf_file"
}

collect_mysql_variables () {
   local file="$1"
   $CMD_MYSQL $EXT_ARGV -ss  -e 'SHOW /*!40100 GLOBAL*/ VARIABLES' > "$file"
}

collect_mysql_status () {
   local file="$1"
   $CMD_MYSQL $EXT_ARGV -ss -e 'SHOW /*!50000 GLOBAL*/ STATUS' > "$file"
}

collect_mysql_databases () {
   local file="$1"
   $CMD_MYSQL $EXT_ARGV -ss -e 'SHOW DATABASES' > "$file" 2>/dev/null
}

collect_mysql_plugins () {
   local file="$1"
   $CMD_MYSQL $EXT_ARGV -ss -e 'SHOW PLUGINS' > "$file" 2>/dev/null
}

collect_mysql_slave_status () {
   local file="$1"
   $CMD_MYSQL $EXT_ARGV -ssE -e 'SHOW SLAVE STATUS' > "$file" 2>/dev/null
}

collect_mysql_innodb_status () {
   local file="$1"
   $CMD_MYSQL $EXT_ARGV -ssE -e 'SHOW /*!50000 ENGINE*/ INNODB STATUS' > "$file" 2>/dev/null
}

collect_mysql_processlist () {
   local file="$1"
   $CMD_MYSQL $EXT_ARGV -ssE -e 'SHOW FULL PROCESSLIST' > "$file" 2>/dev/null
}

collect_mysql_users () {
   local file="$1"
   $CMD_MYSQL $EXT_ARGV -ssE -e 'SELECT COUNT(*), SUM(user=""), SUM(password=""), SUM(password NOT LIKE "*%") FROM mysql.user' > "$file" 2>/dev/null
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
   local defer_file="$2"
   collect_mysql_status "$TMPDIR/defer_gatherer"
   cat "$TMPDIR/defer_gatherer" | join "$status_file" - > "$defer_file"
}

collect_internal_vars () {
   local file="$1"

   local FNV_64=""
   if $CMD_MYSQL $EXT_ARGV -e 'SELECT FNV_64("a")' >/dev/null 2>&1; then
      FNV_64="Enabled";
   else
      FNV_64="Unknown";
   fi

   local now="$($CMD_MYSQL $EXT_ARGV -ss -e 'SELECT NOW()')"
   local user="$($CMD_MYSQL $EXT_ARGV -ss -e 'SELECT CURRENT_USER()')"
   local trigger_count=$($CMD_MYSQL $EXT_ARGV -ss -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TRIGGERS" 2>/dev/null)
   local has_symbols="$(has_symbols "${CMD_MYSQL}")"

   echo "pt-summary-internal-now    $now" >> "$file"
   echo "pt-summary-internal-user   $user" >> "$file"
   echo "pt-summary-internal-FNV_64   $FNV_64" >> "$file"
   echo "pt-summary-internal-trigger_count   $trigger_count" >> "$file"
   echo "pt-summary-internal-symbols   $has_symbols" >> "$file"
}

collect_mysql_info () {
   local dir="$1"
   local prefix="$2"

   collect_mysqld_instances "$dir/${prefix}-mysqld-instances"

   collect_mysql_variables "$dir/${prefix}-mysql-variables"
   collect_mysql_status "$dir/${prefix}-mysql-status"
   collect_mysql_databases "$dir/${prefix}-mysql-databases"
   collect_mysql_plugins "$dir/${prefix}-mysql-plugins"
   collect_mysql_slave_status "$dir/${prefix}-mysql-slave"
   collect_mysql_innodb_status "$dir/${prefix}-innodb-status"
   collect_mysql_processlist "$dir/${prefix}-mysql-processlist"   
   collect_mysql_users "$dir/${prefix}-mysql-users"

   local binlog="$(get_var log_bin "$dir/${prefix}-mysql-variables")"
   if [ "${binlog}" ]; then
      _d "Got a binlog, going to get MASTER LOGS and MASTER STATUS"
      collect_master_logs_status "$dir/${prefix}-mysql-master-logs" "$dir/${prefix}-mysql-master-status"
   fi

   local uptime="$(get_var Uptime "$dir/${prefix}-mysql-status")"
   local current_time="$($CMD_MYSQL $EXT_ARGV -ss -e \
                         "SELECT LEFT(NOW() - INTERVAL ${uptime} SECOND, 16)")"

   local port="$(get_var port "$dir/${prefix}-mysql-variables")"
   local cnf_file=$(find_my_cnf_file "$dir/${prefix}-mysqld-instances" ${port});

   # TODO: Do these require a file of their own?
   echo "pt-summary-internal-current_time    $current_time" >> "$dir/${prefix}-mysql-variables"
   echo "pt-summary-internal-Config_File    $cnf_file" >> "$dir/${prefix}-mysql-variables"
   collect_internal_vars "$dir/${prefix}-mysql-variables"

   if [ -n "${OPT_DUMP_SCHEMAS}" ]; then
      _d "--dump-schemas passed in, dumping early"
      local trg_arg="$( get_mysqldump_args "$dir/${prefix}-mysql-variables" )"
      get_mysqldump_for "$dir/${prefix}-mysqldump" "${trg_arg}" "${OPT_DUMP_SCHEMAS}"
   fi

   # TODO: gather this data in the same format as normal: TS line, stats
   (
      sleep $OPT_SLEEP
      collect_mysql_deferred_status "$dir/${prefix}-mysql-status" "$dir/${prefix}-mysql-status-defer"
   ) &
   _d "Forked child is $!"
}

# ###########################################################################
# End collect_mysql_info package
# ###########################################################################
