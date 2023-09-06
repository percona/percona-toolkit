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
# collect package
# ###########################################################################

# Package: collect
# collect collects system information.

# XXX
# THIS LIB REQUIRES log_warn_die, safeguards, alt_cmds, and subshell!
# XXX

set -u

# Global variables.
CMD_GDB="${CMD_GDB:-"$(_which gdb)"}"
CMD_IOSTAT="${CMD_IOSTAT:-"$(_which iostat)"}"
CMD_MPSTAT="${CMD_MPSTAT:-"$(_which mpstat)"}"
CMD_MYSQL="${CMD_MYSQL:-"$(_which mysql)"}"
CMD_MYSQLADMIN="${CMD_MYSQLADMIN:-"$(_which mysqladmin)"}"
CMD_OPCONTROL="${CMD_OPCONTROL:-"$(_which opcontrol)"}"
CMD_OPREPORT="${CMD_OPREPORT:-"$(_which opreport)"}"
CMD_PMAP="${CMD_PMAP:-"$(_which pmap)"}"
CMD_STRACE="${CMD_STRACE:-"$(_which strace)"}"
CMD_SYSCTL="${CMD_SYSCTL:-"$(_which sysctl)"}"
CMD_TCPDUMP="${CMD_TCPDUMP:-"$(_which tcpdump)"}"
CMD_VMSTAT="${CMD_VMSTAT:-"$(_which vmstat)"}"
CMD_DMESG="${CMD_DMESG:-"$(_which dmesg)"}"

# Try to find command manually.
[ -z "$CMD_SYSCTL" -a -x "/sbin/sysctl" ] && CMD_SYSCTL="/sbin/sysctl"

collect() {
   local d="$1"  # directory to save results in
   local p="$2"  # prefix for each result file

   local cnt=$(($OPT_RUN_TIME / $OPT_SLEEP_COLLECT))

   if [ ! "$OPT_SYSTEM_ONLY" ]; then
      local mysqld_pid=""
      local mysql_version=""
      local mysql_error_log=""
      local tail_error_log_pid=""
      local have_lock_waits_table=""
      local lock_table_p_s=""
      local have_oprofile=""
      local mysqladmin_pid=""
      local mutex=""
      local tcpdump_pid=""
      local ps_instrumentation_enabled=""

      collect_mysql_data_one
   fi

   # Grab a few general things first.  Background all of these so we can start
   # them all up as quickly as possible.
   if [ ! "$OPT_MYSQL_ONLY" ]; then
      collect_system_data
   fi

   # This loop gathers data for the rest of the duration, and defines the time
   # of the whole job.
   log "Loop start: $(date +'TS %s.%N %F %T')"
   local start_time=$(date +'%s')
   local curr_time=$start_time
   local ts="$(date +"TS %s.%N %F %T")"

   while [ $((curr_time - start_time)) -lt $OPT_RUN_TIME ]; do
      if [ ! "$OPT_MYSQL_ONLY" ]; then
         collect_system_data_loop
      fi

      if [ ! "$OPT_SYSTEM_ONLY" ]; then
         collect_mysql_data_loop
      fi

      curr_time=$(date +'%s')
   done
   log "Loop end: $(date +'TS %s.%N %F %T')"

   if [ ! "$OPT_SYSTEM_ONLY" ]; then
      collect_mysql_data_two
   fi

   # Finally, record what system we collected this data from.
   hostname > "$d/$p-hostname"

   # Remove "empty" files, i.e. ones that are truly empty or
   # just contain timestamp lines.  When a command above fails,
   # it may leave an empty file.  But first wait another --run-time
   # seconds for any slow process to finish:
   # https://bugs.launchpad.net/percona-toolkit/+bug/1047701
   wait_for_subshells $OPT_RUN_TIME
   kill_all_subshells
   for file in "$d/$p-"*; do
      # If there's not at least 1 line that's not a TS,
      # then the file is empty.
      if [ -z "$(grep -v '^TS ' --max-count 10 "$file")" ]; then
         log "Removing empty file $file";
         rm "$file"
      fi
   done
}

collect_mysql_data_one() {
   # Get pidof mysqld.
   if [ ! "$OPT_MYSQL_ONLY" ]; then
      port=$($CMD_MYSQL $EXT_ARGV -ss -e 'SELECT @@port')
      mysqld_pid=$(lsof -i ":${port}" | grep -i listen | cut -f 3 -d" ")
   fi

   # Get memory allocation info before anything else.
   if [ "$CMD_PMAP" -a "$mysqld_pid" ]; then
      if $CMD_PMAP --help 2>&1 | grep -- -x >/dev/null 2>&1 ; then
         $CMD_PMAP -x $mysqld_pid > "$d/$p-pmap"
      else
         # Some pmap's apparently don't support -x (issue 116).
         $CMD_PMAP $mysqld_pid > "$d/$p-pmap"
      fi
   fi

   # Getting a GDB stacktrace can be an intensive operation,
   # so do this only if necessary (and possible).
   if [ "$CMD_GDB" -a "$OPT_COLLECT_GDB" -a "$mysqld_pid" ]; then
      $CMD_GDB                     \
         -ex "set pagination 0"    \
         -ex "thread apply all bt" \
         --batch -p $mysqld_pid    \
         >> "$d/$p-stacktrace"
   fi

   # Get MySQL's variables if possible.  Then sleep long enough that we probably
   # complete SHOW VARIABLES if all's well.  (We don't want to run mysql in the
   # foreground, because it could hang.)
   collect_mysql_variables "$d/$p-variables" &
   sleep .5

   # Get the major.minor version number.  Version 3.23 doesn't matter for our
   # purposes, and other releases have x.x.x* version conventions so far.
   mysql_version="$(awk '/^version[^_]/{print substr($2,1,3)}' "$d/$p-variables")"

   # Is MySQL logging its errors to a file?  If so, tail that file.
   mysql_error_log="$(awk '/^log_error\s/{print $2}' "$d/$p-variables")"
   if [ -z "$mysql_error_log" -a "$mysqld_pid" ]; then
      log $mysqld_pid
      # Try getting it from the open filehandle...
      mysql_error_log="$(ls -l /proc/$mysqld_pid/fd | awk '/ 2 ->/{print $NF}')"
   fi

   if [ "$mysql_error_log" -a ! "$OPT_MYSQL_ONLY" ]; then
      log "The MySQL error log seems to be $mysql_error_log"
      tail -f "$mysql_error_log" >"$d/$p-log_error" &
      tail_error_log_pid=$!

      # Send a mysqladmin debug to the server so we can potentially learn about
      # locking etc.
      $CMD_MYSQLADMIN $EXT_ARGV
   else
      log "Could not find the MySQL error log"
   fi
   # Get a sample of these right away, so we can get these without interaction
   # with the other commands we're about to run.
   if [ "${mysql_version}" '>' "5.1" ]; then
      mutex="SHOW ENGINE INNODB MUTEX"
   else
      mutex="SHOW MUTEX STATUS"
   fi
   innodb_status 1
   tokudb_status 1
   rocksdb_status 1

   $CMD_MYSQL $EXT_ARGV -e "$mutex" >> "$d/$p-mutex-status1" &
   open_tables                      >> "$d/$p-opentables1"   &

   # If TCP dumping is specified, start that on the server's port.
   if [ "$CMD_TCPDUMP" -a  "$OPT_COLLECT_TCPDUMP" ]; then
      local port=$(awk '/^port/{print $2}' "$d/$p-variables")
      if [ "$port" ]; then
         $CMD_TCPDUMP -i any -s 4096 -w "$d/$p-tcpdump" port ${port} &
         tcpdump_pid=$!
      fi
   fi

   # Next, start oprofile gathering data during the whole rest of this process.
   # The --init should be a no-op if it has already been init-ed.
   if [ "$CMD_OPCONTROL" -a "$OPT_COLLECT_OPROFILE" ]; then
      if $CMD_OPCONTROL --init; then
         $CMD_OPCONTROL --start --no-vmlinux
         have_oprofile="yes"
      fi
   elif [ "$CMD_STRACE" -a "$OPT_COLLECT_STRACE" -a "$mysqld_pid" ]; then
      # Don't run oprofile and strace at the same time.
      $CMD_STRACE -T -s 0 -f -p $mysqld_pid -o "$d/$p-strace" &
      local strace_pid=$!
   fi

   $CMD_MYSQL $EXT_ARGV -e "SHOW TABLES FROM INFORMATION_SCHEMA" \
      | grep -i "INNODB_LOCK_WAITS" >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      have_lock_waits_table="yes"
   else
      # We cannot simply check version here, because MariaDB uses
      # Information Schema in its 10.x series
      $CMD_MYSQL $EXT_ARGV -e "SHOW TABLES FROM performance_schema" \
         | grep -i "data_lock_waits" >/dev/null 2>&1
      if [ $? -eq 0 ]; then
         have_lock_waits_table="yes"
         lock_table_p_s="yes"
      fi
   fi

   # Collect multiple snapshots of the status variables.  We use
   # mysqladmin -c even though it is buggy and won't stop on its
   # own in 5.1 and newer, because there is a chance that we will
   # get and keep a connection to the database; in troubled times
   # the database tends to exceed max_connections, so reconnecting
   # in the loop tends not to work very well.
   $CMD_MYSQLADMIN $EXT_ARGV ext -i$OPT_SLEEP_COLLECT -c$cnt >>"$d/$p-mysqladmin" &
   mysqladmin_pid=$!

   ps_instrumentation_enabled=$($CMD_MYSQL $EXT_ARGV -e 'SELECT ENABLED FROM performance_schema.setup_instruments WHERE NAME = "transaction";' \
                                      | sed "2q;d" | sed 'y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/')

   if [ $ps_instrumentation_enabled != "yes" ]; then
      log "Performance Schema instrumentation is disabled"
   fi
}

collect_system_data() {
   ps -eaF  >> "$d/$p-ps"  &
   top -bn${OPT_RUN_TIME} >> "$d/$p-top" &

   [ "$mysqld_pid" ] && _lsof $mysqld_pid >> "$d/$p-lsof" &

   if [ "$CMD_SYSCTL" ]; then
      $CMD_SYSCTL -a >> "$d/$p-sysctl" &
   fi

   # collect dmesg events from 60 seconds ago until present
   if [ "$CMD_DMESG" ]; then
      local UPTIME=`cat /proc/uptime | awk '{ print $1 }'`
      local START_TIME=$(echo "$UPTIME 60" | awk '{print ($1 - $2)}')
      $CMD_DMESG  | perl -ne 'm/\[\s*(\d+)\./; if ($1 > '${START_TIME}') { print }' >> "$d/$p-dmesg" &
   fi

   if [ "$CMD_VMSTAT" ]; then
      $CMD_VMSTAT $OPT_SLEEP_COLLECT $cnt >> "$d/$p-vmstat" &
      $CMD_VMSTAT $OPT_RUN_TIME 2 >> "$d/$p-vmstat-overall" &
   fi
   if [ "$CMD_IOSTAT" ]; then
      $CMD_IOSTAT -dx $OPT_SLEEP_COLLECT $cnt >> "$d/$p-iostat" &
      $CMD_IOSTAT -dx $OPT_RUN_TIME 2 >> "$d/$p-iostat-overall" &
   fi
   if [ "$CMD_MPSTAT" ]; then
      $CMD_MPSTAT -P ALL $OPT_SLEEP_COLLECT $cnt >> "$d/$p-mpstat" &
      $CMD_MPSTAT -P ALL $OPT_RUN_TIME 1 >> "$d/$p-mpstat-overall" &
   fi
}

collect_mysql_data_loop() {
   (echo $ts; $CMD_MYSQL $EXT_ARGV -e "SHOW FULL PROCESSLIST\G") \
      >> "$d/$p-processlist" &
   if [ "$have_lock_waits_table" ]; then
      (echo $ts; lock_waits "$d/lock_waits.running")   >>"$d/$p-lock-waits" &
      (echo $ts; transactions) >>"$d/$p-transactions" &
   fi

   if [ "${mysql_version}" '>' "5.6" ] && [ $ps_instrumentation_enabled == "yes" ]; then
      ps_locks_transactions "$d/$p-ps-locks-transactions"
   fi

   if [ "${mysql_version}" '>' "5.6" ]; then
      (echo $ts; ps_prepared_statements "$d/prepared_statements.isrunnning") >> "$d/$p-prepared-statements" &
   fi

   slave_status "$d/$p-slave-status" "${mysql_version}"
}

collect_system_data_loop() {
   # We check the disk, but don't exit, because we need to stop jobs if we
   # need to exit.
   disk_space $d > $d/$p-disk-space
   check_disk_space          \
      $d/$p-disk-space       \
      "$OPT_DISK_BYTES_FREE" \
      "$OPT_DISK_PCT_FREE"   \
      || break

   # Sleep between collect cycles.
   # Synchronize ourselves onto the clock tick, so the sleeps are 1-second
   sleep $(date +'%s.%N' | awk "{print $OPT_SLEEP_COLLECT - (\$1 % $OPT_SLEEP_COLLECT)}")
   ts="$(date +"TS %s.%N %F %T")"

   # #####################################################################
   # Collect data for this cycle.
   # #####################################################################
   if [ -d "/proc" ]; then
      if [ -f "/proc/diskstats" ]; then
         (echo $ts; cat /proc/diskstats) >> "$d/$p-diskstats" &
      fi
      if [ -f "/proc/stat" ]; then
         (echo $ts; cat /proc/stat) >> "$d/$p-procstat" &
      fi
      if [ -f "/proc/vmstat" ]; then
         (echo $ts; cat /proc/vmstat) >> "$d/$p-procvmstat" &
      fi
      if [ -f "/proc/meminfo" ]; then
         (echo $ts; cat /proc/meminfo) >> "$d/$p-meminfo" &
      fi
      if [ -f "/proc/slabinfo" ]; then
         (echo $ts; cat /proc/slabinfo) >> "$d/$p-slabinfo" &
      fi
      if [ -f "/proc/interrupts" ]; then
         (echo $ts; cat /proc/interrupts) >> "$d/$p-interrupts" &
      fi
   fi
   (echo $ts; df -k) >> "$d/$p-df" &
   (echo $ts; netstat -antp) >> "$d/$p-netstat"   &
   (echo $ts; netstat -s)    >> "$d/$p-netstat_s" &
   (echo $ts;
   for node in `ls -d /sys/devices/system/node/node*`; do
      echo `basename $node`; cat "$node/numastat"
   done)                     >> "$d/$p-numastat"   &
}

collect_mysql_data_two() {
   if [ "$have_oprofile" ]; then
      $CMD_OPCONTROL --stop
      $CMD_OPCONTROL --dump

      local oprofiled_pid=$(_pidof oprofiled | awk '{print $1; exit;}')
      if [ "$oprofiled_pid" ]; then
         kill $oprofiled_pid
      else
         warn "Cannot kill oprofiled because its PID cannot be determined"
      fi

      $CMD_OPCONTROL --save=pt_collect_$p

      # Attempt to generate a report; if this fails, then just tell the user
      # how to generate the report.
      local mysqld_path=$(_which mysqld);
      if [ "$mysqld_path" -a -f "$mysqld_path" ]; then
         $CMD_OPREPORT            \
            --demangle=smart      \
            --symbols             \
            --merge tgid          \
            session:pt_collect_$p \
            "$mysqld_path"        \
            > "$d/$p-opreport"
      else
         log "oprofile data saved to pt_collect_$p; you should be able"       \
              "to get a report by running something like 'opreport"           \
              "--demangle=smart --symbols --merge tgid session:pt_collect_$p" \
              "/path/to/mysqld'"                                              \
            > "$d/$p-opreport"
      fi
   elif [ "$CMD_STRACE" -a "$OPT_COLLECT_STRACE" ]; then
      kill -s 2 $strace_pid
      sleep 1
      kill -s 15 $strace_pid
      # Sometimes strace leaves threads/processes in T status.
      [ "$mysqld_pid" ] && kill -s 18 $mysqld_pid
   fi

   innodb_status 2
   tokudb_status 2
   rocksdb_status 2

   $CMD_MYSQL $EXT_ARGV -e "$mutex" >> "$d/$p-mutex-status2" &
   open_tables                      >> "$d/$p-opentables2"   &

   # Kill backgrounded tasks.
   [ "$mysqladmin_pid" ] &&  kill $mysqladmin_pid
   [ "$tail_error_log_pid" ] && kill $tail_error_log_pid
   [ "$tcpdump_pid" ]        && kill $tcpdump_pid
}

open_tables() {
   local open_tables=$($CMD_MYSQLADMIN $EXT_ARGV ext | grep "Open_tables" | awk '{print $4}')
   if [ -n "$open_tables" -a $open_tables -le 1000 ]; then
      $CMD_MYSQL $EXT_ARGV -e 'SHOW OPEN TABLES' &
   else
      log "Logging disabled due to having over 1000 tables open. Number of tables currently open: $open_tables"
   fi
}

lock_waits() {
   local flag_file=$1
   if test -f "$flag_file"; then
      echo "Lock collection already running, skipping this iteration"
   else
      touch "$flag_file"
      local sql1=""
      local sql2=""
      if [ "${lock_table_p_s}" != "yes" ]; then
         sql1="SELECT SQL_NO_CACHE
            CONCAT('thread ', b.trx_mysql_thread_id, ' from ', p.host) AS who_blocks,
            MAX(IF(p.command = \"Sleep\", p.time, 0)) AS idle_in_trx,
            MAX(TIMESTAMPDIFF(SECOND, r.trx_wait_started, CURRENT_TIMESTAMP)) AS max_wait_time,
            COUNT(*) AS num_waiters
         FROM INFORMATION_SCHEMA.INNODB_LOCK_WAITS AS w
         INNER JOIN INFORMATION_SCHEMA.INNODB_TRX AS b ON b.trx_id = w.blocking_trx_id
         INNER JOIN INFORMATION_SCHEMA.INNODB_TRX AS r ON r.trx_id = w.requesting_trx_id
         LEFT JOIN INFORMATION_SCHEMA.PROCESSLIST AS p ON p.id = b.trx_mysql_thread_id
         GROUP BY who_blocks ORDER BY num_waiters DESC\G"

         sql2="SELECT SQL_NO_CACHE
            r.trx_id AS waiting_trx_id,
            r.trx_mysql_thread_id AS waiting_thread,
            TIMESTAMPDIFF(SECOND, r.trx_wait_started, CURRENT_TIMESTAMP) AS wait_time,
            r.trx_query AS waiting_query,
            l.lock_table AS waiting_table_lock,
            b.trx_id AS blocking_trx_id, b.trx_mysql_thread_id AS blocking_thread,
            SUBSTRING(p.host, 1, INSTR(p.host, ':') - 1) AS blocking_host,
            SUBSTRING(p.host, INSTR(p.host, ':') +1) AS blocking_port,
            IF(p.command = \"Sleep\", p.time, 0) AS idle_in_trx,
            b.trx_query AS blocking_query
         FROM INFORMATION_SCHEMA.INNODB_LOCK_WAITS AS w
         INNER JOIN INFORMATION_SCHEMA.INNODB_TRX AS b ON b.trx_id = w.blocking_trx_id
         INNER JOIN INFORMATION_SCHEMA.INNODB_TRX AS r ON r.trx_id = w.requesting_trx_id
         INNER JOIN INFORMATION_SCHEMA.INNODB_LOCKS AS l ON w.requested_lock_id = l.lock_id
         LEFT JOIN INFORMATION_SCHEMA.PROCESSLIST AS p ON p.id = b.trx_mysql_thread_id
         ORDER BY wait_time DESC\G"
      else
         sql1="SELECT SQL_NO_CACHE
            CONCAT('thread ', b.trx_mysql_thread_id, ' from ', p.host) AS who_blocks,
            MAX(IF(p.command = \"Sleep\", p.time, 0)) AS idle_in_trx,
            MAX(TIMESTAMPDIFF(SECOND, r.trx_wait_started, CURRENT_TIMESTAMP)) AS max_wait_time,
            COUNT(*) AS num_waiters
         FROM performance_schema.data_lock_waits AS w
         INNER JOIN INFORMATION_SCHEMA.INNODB_TRX AS b ON b.trx_id = w.BLOCKING_ENGINE_TRANSACTION_ID
         INNER JOIN INFORMATION_SCHEMA.INNODB_TRX AS r ON r.trx_id = w.REQUESTING_ENGINE_TRANSACTION_ID
         LEFT JOIN INFORMATION_SCHEMA.PROCESSLIST AS p ON p.id = b.trx_mysql_thread_id
         GROUP BY who_blocks ORDER BY num_waiters DESC\G"

         sql2="SELECT SQL_NO_CACHE
            r.trx_id AS waiting_trx_id,
            r.trx_mysql_thread_id AS waiting_thread,
            TIMESTAMPDIFF(SECOND, r.trx_wait_started, CURRENT_TIMESTAMP) AS wait_time,
            r.trx_query AS waiting_query,
            CONCAT('\`', l.OBJECT_SCHEMA, '\`.\`', l.OBJECT_NAME, '\`') AS waiting_table_lock,
            b.trx_id AS blocking_trx_id, b.trx_mysql_thread_id AS blocking_thread,
            SUBSTRING(p.host, 1, INSTR(p.host, ':') - 1) AS blocking_host,
            SUBSTRING(p.host, INSTR(p.host, ':') +1) AS blocking_port,
            IF(p.command = \"Sleep\", p.time, 0) AS idle_in_trx,
            b.trx_query AS blocking_query
         FROM performance_schema.data_lock_waits AS w
         INNER JOIN INFORMATION_SCHEMA.INNODB_TRX AS b ON b.trx_id = w.BLOCKING_ENGINE_TRANSACTION_ID
         INNER JOIN INFORMATION_SCHEMA.INNODB_TRX AS r ON r.trx_id = w.REQUESTING_ENGINE_TRANSACTION_ID
         INNER JOIN performance_schema.data_locks AS l ON w.REQUESTING_ENGINE_LOCK_ID = l.ENGINE_LOCK_ID
         LEFT JOIN INFORMATION_SCHEMA.PROCESSLIST AS p ON p.id = b.trx_mysql_thread_id
         ORDER BY wait_time DESC\G"
      fi

      $CMD_MYSQL $EXT_ARGV -e "$sql1"
      $CMD_MYSQL $EXT_ARGV -e "$sql2"

      rm "$flag_file"
   fi
}

transactions() {
   $CMD_MYSQL $EXT_ARGV -e "SELECT SQL_NO_CACHE * FROM INFORMATION_SCHEMA.INNODB_TRX ORDER BY trx_id\G"
   if [ "${lock_table_p_s}" != "yes" ]; then
      $CMD_MYSQL $EXT_ARGV -e "SELECT SQL_NO_CACHE * FROM INFORMATION_SCHEMA.INNODB_LOCKS ORDER BY lock_trx_id\G"
      $CMD_MYSQL $EXT_ARGV -e "SELECT SQL_NO_CACHE * FROM INFORMATION_SCHEMA.INNODB_LOCK_WAITS ORDER BY blocking_trx_id, requesting_trx_id\G"
   else
      $CMD_MYSQL $EXT_ARGV -e "SELECT SQL_NO_CACHE * FROM performance_schema.data_locks ORDER BY ENGINE_TRANSACTION_ID\G"
      $CMD_MYSQL $EXT_ARGV -e "SELECT SQL_NO_CACHE * FROM performance_schema.data_lock_waits ORDER BY BLOCKING_ENGINE_TRANSACTION_ID, REQUESTING_ENGINE_TRANSACTION_ID\G"
   fi
}

tokudb_status() {
    local n=$1

    has_tokudb=`$CMD_MYSQL $EXT_ARGV -e "SHOW ENGINES" | grep -i 'tokudb'`
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
       $CMD_MYSQL $EXT_ARGV -e "SHOW ENGINE TOKUDB STATUS\G" \
         >> "$d/$p-tokudbstatus$n" || rm -f "$d/$p-tokudbstatus$n"
    fi
}

innodb_status() {
   local n=$1

   local innostat=""

   $CMD_MYSQL $EXT_ARGV -e "SHOW /*!40100 ENGINE*/ INNODB STATUS\G" \
      >> "$d/$p-innodbstatus$n"
   grep "END OF INNODB" "$d/$p-innodbstatus$n" >/dev/null || {
      if [ -d /proc -a -d /proc/$mysqld_pid ]; then
         for fd in /proc/$mysqld_pid/fd/*; do
            file $fd | grep deleted >/dev/null && {
               grep 'INNODB' $fd >/dev/null && {
                  cat $fd > "$d/$p-innodbstatus$n"
                  break
               }
            }
         done
      fi
   }
}

rocksdb_status() {
    local n=$1

    has_rocksdb=`$CMD_MYSQL $EXT_ARGV -e "SHOW ENGINES" | grep -i 'rocksdb'`
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        $CMD_MYSQL $EXT_ARGV -e "SHOW ENGINE ROCKSDB STATUS\G" \
                   >> "$d/$p-rocksdbstatus$n" || rm -f "$d/$p-rocksdbstatus$n"
    fi
}

ps_locks_transactions() {
   local outfile=$1

   $CMD_MYSQL $EXT_ARGV -e 'select @@performance_schema' | grep "1" &>/dev/null

   if [ $? -eq 0 ]; then
      local status="select t.processlist_id, ml.* from performance_schema.metadata_locks ml join performance_schema.threads t on (ml.owner_thread_id=t.thread_id)\G"
      echo -e "\n$status\n" >> $outfile
      $CMD_MYSQL $EXT_ARGV -e "$status" >> $outfile

      local status="select t.processlist_id, th.* from performance_schema.table_handles th left join performance_schema.threads t on (th.owner_thread_id=t.thread_id)\G"
      echo -e "\n$status\n" >> $outfile
      $CMD_MYSQL $EXT_ARGV -e "$status" >> $outfile

      local status="select t.processlist_id, et.* from performance_schema.events_transactions_current et join performance_schema.threads t using(thread_id)\G"
      echo -e "\n$status\n" >> $outfile
      $CMD_MYSQL $EXT_ARGV -e "$status" >> $outfile

      local status="select t.processlist_id, et.* from performance_schema.events_transactions_history_long et join performance_schema.threads t using(thread_id)\G"
      echo -e "\n$status\n" >> $outfile
      $CMD_MYSQL $EXT_ARGV -e "$status" >> $outfile
  else
      echo "Performance schema is not enabled" >> $outfile
   fi

}

ps_prepared_statements() {
# PS-2033:
# If no flag file exists, create it, then collect data
# After data collected, remove the file
# If flag file exists, skip current iteration
   local flag_file=$1
   if test -f "$flag_file"; then
      echo "Prepared statements collection already running, skipping this iteration"
   else
      touch "$flag_file"
      $CMD_MYSQL $EXT_ARGV -e "SELECT t.processlist_id, pse.* \
                               FROM performance_schema.prepared_statements_instances pse \
                               JOIN performance_schema.threads t \
                               ON (pse.OWNER_THREAD_ID=t.thread_id)\G"
      rm "$flag_file"
   fi
}

slave_status() {
   local outfile=$1
   local mysql_version=$2

   if [ "${mysql_version}" '<' "8.1" ]; then
      local sql="SHOW SLAVE STATUS\G"
   else
      local sql="SHOW REPLICA STATUS\G"
   fi

   echo -e "\n$sql\n" >> $outfile
   $CMD_MYSQL $EXT_ARGV -e "$sql" >> $outfile

   if [ "${mysql_version}" '>' "5.6" ]; then
      local sql="SELECT * FROM performance_schema.replication_connection_configuration JOIN performance_schema.replication_applier_configuration USING(channel_name)\G"
      echo -e "\n$sql\n" >> $outfile
      $CMD_MYSQL $EXT_ARGV -e "$sql" >> $outfile

      sql="SELECT * FROM performance_schema.replication_connection_status\G"
      echo -e "\n$sql\n" >> $outfile
      $CMD_MYSQL $EXT_ARGV -e "$sql" >> $outfile

      sql="SELECT * FROM performance_schema.replication_applier_status JOIN performance_schema.replication_applier_status_by_coordinator USING(channel_name)\G"
      echo -e "\n$sql\n" >> $outfile
      $CMD_MYSQL $EXT_ARGV -e "$sql" >> $outfile
   fi

}

collect_mysql_variables() {
   local outfile=$1

   local sql="SHOW GLOBAL VARIABLES"
   echo -e "\n$sql\n" >> $outfile
   $CMD_MYSQL $EXT_ARGV -e "$sql" >> $outfile

   sql="select * from performance_schema.variables_by_thread order by thread_id, variable_name;"
   echo -e "\n$sql\n" >> $outfile
   $CMD_MYSQL $EXT_ARGV -e "$sql" >> $outfile

   sql="select * from performance_schema.user_variables_by_thread order by thread_id, variable_name;"
   echo -e "\n$sql\n" >> $outfile
   $CMD_MYSQL $EXT_ARGV -e "$sql" >> $outfile

   sql="select * from performance_schema.status_by_thread order by thread_id, variable_name; "
   echo -e "\n$sql\n" >> $outfile
   $CMD_MYSQL $EXT_ARGV -e "$sql" >> $outfile

}

# ###########################################################################
# End collect package
# ###########################################################################
