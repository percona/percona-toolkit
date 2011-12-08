# This program is copyright 2011 Percona Inc.
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

set -u

# Global variables.
CMD_GDB=${CMD_GDB:-"gdb"}
CMD_IOSTAT=${CMD_IOSTAT:-"iostat"}
CMD_MPSTAT=${CMD_MPSTAT:-"mpstat"}
CMD_MYSQL=${CMD_MSSQL:-"mysql"}
CMD_MYSQLADMIN=${CMD_MYSQL_ADMIN:-"mysqladmin"}
CMD_OPCONTROL=${CMD_OPCONTROL:-"opcontrol"}
CMD_OPREPORT=${CMD_OPREPORT:-"opreport"}
CMD_PMAP=${CMD_PMAP:-"pmap"}
CMD_STRACE=${CMD_STRACE:-"strace"}
CMD_TCPDUMP=${CMD_TCPDUMP:-"tcpdump"}
CMD_VMSTAT=${CMD_VMSTAT:-"vmstat"}

collect() {
   local d=$1  # directory to save results in
   local p=$2  # prefix for each result file

   # Get pidof mysqld; pidof doesn't exist on some systems.  We try our best...
   local mysqld_pid=$(pidof -s mysqld);
   if [ -z "$mysqld_pid" ]; then
      mysqld_pid=$(pgrep -o -x mysqld);
   fi
   if [ -z "$mysqld_pid" ]; then
      mysqld_pid=$(ps -eaf | grep 'mysql[d]' | grep -v mysqld_safe | awk '{print $2}' | head -n1);
   fi

   # Get memory allocation info before anything else.
   if [ -x "$CMD_PMAP" -a "$mysqld_pid" ]; then
      if $CMD_PMAP --help 2>&1 | grep -- -x >/dev/null 2>&1 ; then
         $CMD_PMAP -x $mysqld_pid > "$d/$p-pmap"
      else
         # Some pmap's apparently don't support -x (issue 116).
         $CMD_PMAP $mysqld_pid > "$d/$p-pmap"
      fi
   fi

   # Getting a GDB stacktrace can be an intensive operation,
   # so do this only if necessary.
   if [ "$OPT_COLLECT_GDB" = "yes" -a "$mysqld_pid" ]; then
      $CMD_GDB                     \
         -ex "set pagination 0"    \
         -ex "thread apply all bt" \
         --batch -p $mysqld_pid    \
         >> "$d/$p-stacktrace"
   else
      echo "GDB (--collect-gdb) was not enabled" >> "$d/$p-stacktrace"
   fi

   # Get MySQL's variables if possible.  Then sleep long enough that we probably
   # complete SHOW VARIABLES if all's well.  (We don't want to run mysql in the
   # foreground, because it could hang.)
   $CMD_MYSQL "$EXT_ARGV" -e 'SHOW GLOBAL VARIABLES' >> "$d/$p-variables" 2>&1 &
   sleep .2

   # Get the major.minor version number.  Version 3.23 doesn't matter for our
   # purposes, and other releases have x.x.x* version conventions so far.
   local mysql_version="$(awk '/^version[^_]/{print substr($2,1,3)}' "$d/$p-variables")"

   # Is MySQL logging its errors to a file?  If so, tail that file.
   local mysql_error_log="$(awk '/log_error/{print $2}' "$d/$p-variables")"
   if [ -z "$mysql_error_log" -a "$mysqld_pid" ]; then
      # Try getting it from the open filehandle...
      mysql_error_log="$(ls -l /proc/$mysqld_pid/fd | awk '/ 2 ->/{print $NF}')"
   fi

   local tail_error_log_pid=""
   if [ "$mysql_error_log" ]; then
      echo "The MySQL error log seems to be ${mysql_error_log}"
      tail -f "$mysql_error_log" >"$d/$p-log_error" 2>&1 &
      tail_error_log_pid=$!
      # Send a mysqladmin debug to the server so we can potentially learn about
      # locking etc.
      $CMD_MYSQLADMIN "$EXT_ARGV" debug
   else
      echo "Could not find the MySQL error log"
   fi

   # Get a sample of these right away, so we can get these without interaction
   # with the other commands we're about to run.
   local innostat="SHOW /*!40100 ENGINE*/ INNODB STATUS\G"
   if [ "${mysql_version}" '>' "5.1" ]; then
      local mutex="SHOW ENGINE INNODB MUTEX"
   else
      local mutex="SHOW MUTEX STATUS"
   fi
   $CMD_MYSQL "$EXT_ARGV" -e "$innostat" >> "$d/$p-innodbstatus1" 2>&1 &
   $CMD_MYSQL "$EXT_ARGV" -e "$mutex"    >> "$d/$p-mutex-status1" 2>&1 &
   open_tables                           >> "$d/$p-opentables1"   2>&1 &

   # If TCP dumping is specified, start that on the server's port.
   local tcpdump_pid=""
   if [ "$OPT_COLLECT_TCPDUMP" = "yes" ]; then
      local port=$(awk '/^port/{print $2}' "$d/$p-variables")
      if [ "$port" ]; then
         $CMD_TCPDUMP -i any -s 4096 -w "$d/$p-tcpdump" port ${port} &
         tcpdump_pid=$!
      fi
   fi

   # Next, start oprofile gathering data during the whole rest of this process.
   # The --init should be a no-op if it has already been init-ed.
   local have_oprofile="no"
   if [ "$OPT_COLLECT_OPROFILE" = "yes" ]; then
      if $CMD_OPCONTROL --init; then
         $CMD_OPCONTROL --start --no-vmlinux
         have_oprofile="yes"
      fi
   elif [ "$OPT_COLLECT_STRACE" = "yes" ]; then
      # Don't run oprofile and strace at the same time.
      $CMD_STRACE -T -s 0 -f -p $mysqld_pid > "${DEST}/$d-strace" 2>&1 &
      local strace_pid=$!
   fi

   # Grab a few general things first.  Background all of these so we can start
   # them all up as quickly as possible.  
   ps -eaf                            >> "$d/$p-ps"             2>&1 &
   sysctl -a                          >> "$d/$p-sysctl"         2>&1 &
   top -bn1                           >> "$d/$p-top"            2>&1 &
   $CMD_VMSTAT 1 $OPT_INTERVAL        >> "$d/$p-vmstat"         2>&1 &
   $CMD_VMSTAT $OPT_INTERVAL 2        >> "$d/$p-vmstat-overall" 2>&1 &
   $CMD_IOSTAT -dx  1 $OPT_INTERVAL   >> "$d/$p-iostat"         2>&1 &
   $CMD_IOSTAT -dx  $OPT_INTERVAL 2   >> "$d/$p-iostat-overall" 2>&1 &
   $CMD_MPSTAT -P ALL 1 $OPT_INTERVAL >> "$d/$p-mpstat"         2>&1 &
   $CMD_MPSTAT -P ALL $OPT_INTERVAL 1 >> "$d/$p-mpstat-overall" 2>&1 &
   lsof -nP -p $mysqld_pid -bw        >> "$d/$p-lsof"           2>&1 &

   # Collect multiple snapshots of the status variables.  We use
   # mysqladmin -c even though it is buggy and won't stop on its
   # own in 5.1 and newer, because there is a chance that we will
   # get and keep a connection to the database; in troubled times
   # the database tends to exceed max_connections, so reconnecting
   # in the loop tends not to work very well.
   $CMD_MYSQLADMIN "$EXT_ARGV" ext -i1 -c$OPT_RUN_TIME \
      >> "$d/$p-mysqladmin" 2>&1 &
   local mysqladmin_pid=$!

   # This loop gathers data for the rest of the duration, and defines the time
   # of the whole job.
   echo "Loop start: $(date +'TS %s.%N %F %T')"
   for loopno in $(_seq $OPT_RUN_TIME); do
      # We check the disk, but don't exit, because we need to stop jobs if we
      # need to exit.
      disk_space $d > $d/$p-disk-space
      check_disk_space          \
         $d/$p-disk-space       \
         "$OPT_DISK_BYTE_LIMIT" \
         "$OPT_DISK_PCT_LIMIT"  \
         || break

      # Synchronize ourselves onto the clock tick, so the sleeps are 1-second
      sleep $(date +%s.%N | awk '{print 1 - ($1 % 1)}')
      local ts="$(date +"TS %s.%N %F %T")"

      # Collect the stuff for this cycle
      (cat /proc/diskstats  2>&1; echo $ts) >> "$d/$p-diskstats"   &
      (cat /proc/stat       2>&1; echo $ts) >> "$d/$p-procstat"    &
      (cat /proc/vmstat     2>&1; echo $ts) >> "$d/$p-procvmstat"  &
      (cat /proc/meminfo    2>&1; echo $ts) >> "$d/$p-meminfo"     &
      (cat /proc/slabinfo   2>&1; echo $ts) >> "$d/$p-slabinfo"    &
      (cat /proc/interrupts 2>&1; echo $ts) >> "$d/$p-interrupts"  &
      (df -h                2>&1; echo $ts) >> "$d/$p-df"          &
      (netstat -antp        2>&1; echo $ts) >> "$d/$p-netstat"     &
      (netstat -s           2>&1; echo $ts) >> "$d/$p-netstat_s"   &

      ($CMD_MYSQL "$EXT_ARGV" -e "SHOW FULL PROCESSLIST\G" 2>&1; echo $ts) \
         >> "$d/$p-processlist"
   done
   echo "Loop end: $(date +'TS %s.%N %F %T')"

   if [ "$have_oprofile" = "yes" ]; then
      $CMD_OPCONTROL --stop
      $CMD_OPCONTROL --dump
      kill $(pidof oprofiled);  # TODO: what if system doesn't have pidof?
      $CMD_OPCONTROL --save=pt_collect_$p

      # Attempt to generate a report; if this fails, then just tell the user
      # how to generate the report.
      local mysqld_path=$(which mysqld);
      if [ "$mysqld_path" -a -f "$mysqld_path" ]; then
         $CMD_OPREPORT            \
            --demangle=smart      \
            --symbols             \
            --merge tgid          \
            session:pt_collect_$p \
            "$mysqld_path"        \
            > "$d/$p-opreport"
      else
         echo "oprofile data saved to pt_collect_$p; you should be able"      \
              "to get a report by running something like 'opreport"           \
              "--demangle=smart --symbols --merge tgid session:pt_collect_$p" \
              "/path/to/mysqld'"                                              \
            > "$d/$p-opreport"
      fi
   elif [ "$OPT_COLLECT_STRACE" = "yes" ]; then
      kill -s 2 $strace_pid
      sleep 1
      kill -s 15 $strace_pid
      # Sometimes strace leaves threads/processes in T status.
      kill -s 18 $mysqld_pid
   fi

   $CMD_MYSQL "$EXT_ARGV" -e "$innostat" >> "$d/$p-innodbstatus2" 2>&1 &
   $CMD_MYSQL "$EXT_ARGV" -e "$mutex"    >> "$d/$p-mutex-status2" 2>&1 &
   open_tables                           >> "$d/$p-opentables2"   2>&1 &

   # Kill backgrounded tasks.
   kill $mysqladmin_pid
   [ "$tail_error_log_pid" ] && kill $tail_error_log_pid
   [ "$tcpdump_pid" ] && kill $tcpdump_pid

   # Finally, record what system we collected this data from.
   hostname > "$d/$p-hostname"
}

open_tables() {
   local open_tables=$($CMD_MYSQLADMIN "$EXT_ARGV" ext | grep "Open_tables" | awk '{print $4}')
   if [ -n "$open_tables" -a $open_tables -le 1000 ]; then
      $CMD_MYSQL "$EXT_ARGV" -e 'SHOW OPEN TABLES' 2>&1 &
   else
      echo "Too many open tables: $open_tables"
   fi
}

# ###########################################################################
# End collect package
# ###########################################################################
