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
# report_mysql_info package
# ###########################################################################

# Package: report_mysql_info
# Report various aspects of MySQL

set -u
POSIXLY_CORRECT=1

# Accepts a number of seconds, and outputs a d+h:m:s formatted string
secs_to_time () {
   awk -v sec="$1" 'BEGIN {
      printf( "%d+%02d:%02d:%02d", sec / 86400, (sec % 86400) / 3600, (sec % 3600) / 60, sec % 60);
   }'
}

# Returns "Enabled", "Disabled", or "Not Supported" depending on whether the
# variable exists and is ON or enabled.  You can pass 2nd and 3rd variables to
# control whether the variable should be 'gt' (numeric greater than) or 'eq'
# (string equal) to some value.
feat_on() {
   local file="$1"
   local varname="$2"
   [ -e "$file" ] || return

   if [ "$( grep "$varname" "${file}" )" ]; then
      local var="$(awk "\$1 ~ /^$2$/ { print \$2 }" $file)"
      if [ "${var}" = "ON" ]; then
         echo "Enabled"
      elif [ "${var}" = "OFF" -o "${var}" = "0" -o -z "${var}" ]; then
         echo "Disabled"
      elif [ "${3:-""}" = "ne" ]; then
         if [ "${var}" != "$4" ]; then
            echo "Enabled"
         else
            echo "Disabled"
         fi
      elif [ "${3:-""}" = "gt" ]; then
         if [ "${var}" -gt "$4" ]; then
            echo "Enabled"
         else
            echo "Disabled"
         fi
      elif [ "${var}" ]; then
         echo "Enabled"
      else
         echo "Disabled"
      fi
   else
      echo "Not Supported"
   fi
}

feat_on_renamed () {
   local file="$1"
   shift;

   for varname in "$@"; do
      local feat_on="$( feat_on "$file" $varname )"
      if [ "${feat_on:-"Not Supported"}" != "Not Supported" ]; then
         echo $feat_on
         return
      fi
   done

   echo "Not Supported"
}

get_table_cache () {
   local file="$1"

   [ -e "$file" ] || return

   local table_cache=""
   if [ "$( get_var table_open_cache "${file}" )" ]; then
      table_cache="$(get_var table_open_cache "${file}")"
   else
      table_cache="$(get_var table_cache "${file}")"
   fi
   echo ${table_cache:-0}
}

# Gets the status of a plugin, or returns "Not found"
get_plugin_status () {
   local file="$1"
   local plugin="$2"

   local status="$(grep -w "$plugin" "$file" | awk '{ print $2 }')"

   echo ${status:-"Not found"}
}

# ##############################################################################
# Functions for parsing specific files and getting desired info from them.
# These are called from within main() and are separated so they can be tested
# easily.
# ##############################################################################

# Parses the output of 'ps -e -o args | grep mysqld' or 'ps auxww...'
_NO_FALSE_NEGATIVES=""
parse_mysqld_instances () {
   local file="$1"
   local variables_file="$2"

   local socket=""
   local port=""
   local datadir=""
   local defaults_file=""

   [ -e "$file" ] || return

   echo "  Port  Data Directory             Nice OOM Socket"
   echo "  ===== ========================== ==== === ======"

   grep '/mysqld ' "$file" | while read line; do
      local pid=$(echo "$line" | awk '{print $1;}')
      for word in ${line}; do
         # Some grep doesn't have -o, so I have to pull out the words I want by
         # looking at each word
         if echo "${word}" | grep -- "--socket=" > /dev/null; then
            socket="$(echo "${word}" | cut -d= -f2)"
         fi
         if echo "${word}" | grep -- "--port=" > /dev/null; then
            port="$(echo "${word}" | cut -d= -f2)"
         fi
         if echo "${word}" | grep -- "--datadir=" > /dev/null; then
            datadir="$(echo "${word}" | cut -d= -f2)"
         fi
         if echo "${word}" | grep -- "--defaults-file=" > /dev/null; then
            defaults_file="$(echo "${word}" | cut -d= -f2)"
         fi
      done
      
      if [ -n "${defaults_file:-""}" -a -r "${defaults_file:-""}" ]; then
         socket="${socket:-"$(grep "^socket\>" "$defaults_file" | tail -n1 | cut -d= -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')"}"
         port="${port:-"$(grep "^port\>" "$defaults_file" | tail -n1 | cut -d= -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')"}"
         datadir="${datadir:-"$(grep "^datadir\>" "$defaults_file" | tail -n1 | cut -d= -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')"}"
      fi

      local nice="$(get_var "internal::nice_of_$pid" "$variables_file")"
      local oom="$(get_var "internal::oom_of_$pid" "$variables_file")"
      # Only used during testing
      if [ -n "${_NO_FALSE_NEGATIVES}" ]; then
         nice="?"
         oom="?"
      fi
      printf "  %5s %-26s %-4s %-3s %s\n" "${port}" "${datadir}" "${nice:-"?"}" "${oom:-"?"}" "${socket}"
      
      # Need to unset all of them in case the next process uses --defaults-file
      defaults_file=""
      socket=""
      port=""
      datadir=""
   done
}

# Gets the MySQL system time.  Uses input from $MYSQL_VARIABLES_FILE.
get_mysql_timezone () {
   local file="$1"

   [ -e "$file" ] || return

   local tz="$(get_var time_zone "${file}")"
   if [ "${tz}" = "SYSTEM" ]; then
      tz="$(get_var system_time_zone "${file}")"
   fi
   echo "${tz}"
}

# Gets the MySQL system version.
get_mysql_version () {
   local file="$1"

   name_val Version "$(get_var version "${file}") $(get_var version_comment "${file}")"
   name_val "Built On" "$(get_var version_compile_os "${file}") $(get_var version_compile_machine "${file}")"
}

# Gets the system start and uptime in human readable format.
get_mysql_uptime () {
   local uptime="$1"
   local restart="$2"
   uptime="$(secs_to_time ${uptime})"
   echo "${restart} (up ${uptime})"
}

# Summarizes the output of SHOW MASTER LOGS.
summarize_binlogs () {
   local file="$1"

   [ -e "$file" ] || return

   local size="$(awk '{t += $2} END{printf "%0.f\n", t}' "$file")"
   name_val "Binlogs" $(wc -l "$file")
   name_val "Zero-Sized" $(grep -c '\<0$' "$file")
   name_val "Total Size" $(shorten ${size} 1)
}

format_users () {
   local file="$1"
   [ -e "$file" ] || return
   awk '{printf "%d users, %d anon, %d w/o pw, %d old pw\n", $1, $2, $3, $4}' "${file}"
}

# Print out binlog_do_db and binlog_ignore_db
format_binlog_filters () {
   local file="$1"
   [ -e "$file" ] || return
   name_val "binlog_do_db" "$(cut -f3 "$file")"
   name_val "binlog_ignore_db" "$(cut -f4 "$file")"
}

# Takes as input a file that has two samples of SHOW STATUS, columnized next to
# each other.  Outputs fuzzy-ed numbers:
# absolute, all-time per second, and per-second over the interval between the
# samples.  Omits any rows that are all zeroes.
format_status_variables () {
   local file="$1"
   [ -e "$file" ] || return

   # First, figure out the intervals.
   utime1="$(awk '/Uptime /{print $2}' "$file")";
   utime2="$(awk '/Uptime /{print $3}' "$file")";
   awk "
   BEGIN {
      utime1 = ${utime1};
      utime2 = ${utime2};
      udays  = utime1 / 86400;
      udiff  = utime2 - utime1;
      printf(\"%-35s %11s %11s %11s\\n\", \"Variable\", \"Per day\", \"Per second\", udiff \" secs\");
   }
   \$2 ~ /^[0-9]*\$/ {
      if ( \$2 > 0 && \$2 < 18446744073709551615 ) {
         if ( udays > 0 ) {
            fuzzy_var=\$2 / udays;
            ${fuzzy_formula};
            perday=fuzzy_var;
         }
         if ( utime1 > 0 ) {
            fuzzy_var=\$2 / utime1;
            ${fuzzy_formula};
            persec=fuzzy_var;
         }
         if ( udiff > 0 ) {
            fuzzy_var=(\$3 - \$2) / udiff;
            ${fuzzy_formula};
            nowsec=fuzzy_var;
         }
         perday = int(perday);
         persec = int(persec);
         nowsec = int(nowsec);
         if ( perday + persec + nowsec > 0 ) {
            # We do the format in this roundabout way because we want two clashing
            # behaviors: If something is zero, just print the space padding,
            # however, if it's any other number, we want that. Problem: %s alone
            # might use scientific notation, and we can't use %11.f for both cases
            # as it would turn the empty string into a zero. So use both.
            perday_format=\"%11.f\";
            persec_format=\"%11.f\";
            nowsec_format=\"%11.f\";
            if ( perday == 0 ) { perday = \"\"; perday_format=\"%11s\"; }
            if ( persec == 0 ) { persec = \"\"; persec_format=\"%11s\"; }
            if ( nowsec == 0 ) { nowsec = \"\"; nowsec_format=\"%11s\"; }
            format=\"%-35s \" perday_format \" \" persec_format \" \" nowsec_format \"\\n\";
            printf(format, \$1, perday, persec, nowsec);
         }
      }
   }" "$file"
}

# Slices the processlist a bunch of different ways.  The processlist should be
# created with the \G flag so it's vertical.
# The parsing is a bit awkward because different
# versions of awk have limitations like "too many fields on line xyz".  So we
# use 'cut' to shorten the lines.  We count all things into temporary variables
# for each process in the processlist, and when we hit the Info: line which
# ought to be the last line in the process, we decide what to do with the temp
# variables.  If we're summarizing Command, we count everything; otherwise, only
# non-Sleep processes get counted towards the sum and max of Time.
summarize_processlist () {
   local file="$1"

   [ -e "$file" ] || return

   for param in Command User Host db State; do
      echo
      printf '  %-30s %8s %7s %9s %9s\n' \
         "${param}" "COUNT(*)" Working "SUM(Time)" "MAX(Time)"
      echo "  ------------------------------" \
         "-------- ------- --------- ---------"
      cut -c1-80 "$file" \
         | awk "
         \$1 == \"${param}:\" {
            p = substr(\$0, index(\$0, \":\") + 2);
            if ( index(p, \":\") > 0 ) {
               p = substr(p, 1, index(p, \":\") - 1);
            }
            if ( length(p) > 30 ) {
               p = substr(p, 1, 30);
            }
         }
         \$1 == \"Time:\" {
            t = \$2;
         }
         \$1 == \"Command:\" {
            c = \$2;
         }
         \$1 == \"Info:\" {
            count[p]++;
            if ( c == \"Sleep\" ) {
               sleep[p]++;
            }
            if ( \"${param}\" == \"Command\" || c != \"Sleep\" ) {
               time[p] += t;
               if ( t > mtime[p] ) { mtime[p] = t; }
            }
         }
         END {
            for ( p in count ) {
               fuzzy_var=count[p]-sleep[p]; ${fuzzy_formula} fuzzy_work=fuzzy_var;
               fuzzy_var=count[p];          ${fuzzy_formula} fuzzy_count=fuzzy_var;
               fuzzy_var=time[p];           ${fuzzy_formula} fuzzy_time=fuzzy_var;
               fuzzy_var=mtime[p];          ${fuzzy_formula} fuzzy_mtime=fuzzy_var;
               printf \"  %-30s %8d %7d %9d %9d\n\", p, fuzzy_count, fuzzy_work, fuzzy_time, fuzzy_mtime;
            }
         }
      " | sort
   done
   echo
}

# Pretty-prints the my.cnf file.
pretty_print_cnf_file () {
   local file="$1"

   [ -e "$file" ] || return

   perl -n -l -e '
      my $line = $_;
      if ( $line =~ /^\s*[a-zA-Z[]/ ) { 
         if ( $line=~/\s*(.*?)\s*=\s*(.*)\s*$/ ) { 
            printf("%-35s = %s\n", $1, $2)  
         } 
         elsif ( $line =~ /\s*\[/ ) { 
            print "\n$line" 
         } else {
            print $line
         } 
      }' "$file"

}


find_checkpoint_age() {
   local file="$1"
   awk '
   /Log sequence number/{
      if ( $5 ) {
         lsn = $5 + ($4 * 4294967296);
      }
      else {
         lsn = $4;
      }
   }
   /Last checkpoint at/{
      if ( $5 ) {
         print lsn - ($5 + ($4 * 4294967296));
      }
      else {
         print lsn - $4;
      }
   }
   ' "$file"
}

find_pending_io_reads() {
   local file="$1"

   [ -e "$file" ] || return

   awk '
   /Pending normal aio reads/ {
      normal_aio_reads  = substr($5, 1, index($5, ","));
   }
   /ibuf aio reads/ {
      ibuf_aio_reads = substr($4, 1, index($4, ","));
   }
   /pending preads/ {
      preads = $1;
   }
   /Pending reads/ {
      reads = $3;
   }
   END {
      printf "%d buf pool reads, %d normal AIO", reads, normal_aio_reads;
      printf ", %d ibuf AIO, %d preads", ibuf_aio_reads, preads;
   }
   ' "${file}"
}

find_pending_io_writes() {
   local file="$1"

   [ -e "$file" ] || return

   awk '
   /aio writes/ {
      aio_writes = substr($NF, 1, index($NF, ","));
   }
   /ibuf aio reads/ {
      log_ios = substr($7, 1, index($7, ","));
      sync_ios = substr($10, 1, index($10, ","));
   }
   /pending log writes/ {
      log_writes = $1;
      chkp_writes = $5;
   }
   /pending pwrites/ {
      pwrites = $4;
   }
   /Pending writes:/ {
      lru = substr($4, 1, index($4, ","));
      flush_list = substr($7, 1, index($7, ","));
      single_page = $NF;
   }
   END {
      printf "%d buf pool (%d LRU, %d flush list, %d page); %d AIO, %d sync, %d log IO (%d log, %d chkp); %d pwrites", lru + flush_list + single_page, lru, flush_list, single_page, aio_writes, sync_ios, log_ios, log_writes, chkp_writes, pwrites;
   }
   ' "${file}"
}

find_pending_io_flushes() {
   local file="$1"

   [ -e "$file" ] || return

   awk '
   /Pending flushes/ {
      log_flushes = substr($5, 1, index($5, ";"));
      buf_pool = $NF;
   }
   END {
      printf "%d buf pool, %d log", buf_pool, log_flushes;
   }
   ' "${file}"
}

summarize_undo_log_entries() {
   local file="$1"

   [ -e "$file" ] || return

   grep 'undo log entries' "${file}" \
      | sed -e 's/^.*undo log entries \([0-9]*\)/\1/' \
      | awk '
      {
         count++;
         sum += $1;
         if ( $1 > max ) {
            max = $1;
         }
      }
      END {
         printf "%d transactions, %d total undo, %d max undo\n", count, sum, max;
      }'
}

find_max_trx_time() {
   local file="$1"

   [ -e "$file" ] || return

   awk '
   BEGIN {
      max = 0;
   }
   /^---TRANSACTION.* sec,/ {
      for ( i = 0; i < 7; ++i ) {
         if ( $i == "sec," ) {
            j = i-1;
            if ( max < $j ) {
               max = $j;
            }
         }
      }
   }
   END {
      print max;
   }' "${file}"
}

find_transation_states () {
   local file="$1"
   local tmpfile="$PT_TMPDIR/find_transation_states.tmp"

   [ -e "$file" ] || return

   awk -F, '/^---TRANSACTION/{print $2}' "${file}"   \
                        | sed -e 's/ [0-9]* sec.*//' \
                        | sort                       \
                        | uniq -c > "${tmpfile}"
   group_concat "${tmpfile}"
}

# Summarizes various things about InnoDB status that are not easy to see by eye.
format_innodb_status () {
   local file=$1

   [ -e "$file" ] || return

   name_val "Checkpoint Age"      "$(shorten $(find_checkpoint_age "${file}") 0)"
   name_val "InnoDB Queue"        "$(awk '/queries inside/{print}' "${file}")"
   name_val "Oldest Transaction"  "$(find_max_trx_time "${file}") Seconds";
   name_val "History List Len"    "$(awk '/History list length/{print $4}' "${file}")"
   name_val "Read Views"          "$(awk '/read views open inside/{print $1}' "${file}")"
   name_val "Undo Log Entries"    "$(summarize_undo_log_entries "${file}")"
   name_val "Pending I/O Reads"   "$(find_pending_io_reads "${file}")"
   name_val "Pending I/O Writes"  "$(find_pending_io_writes "${file}")"
   name_val "Pending I/O Flushes" "$(find_pending_io_flushes "${file}")"
   name_val "Transaction States"  "$(find_transation_states "${file}" )"
   if grep 'TABLE LOCK table' "${file}" >/dev/null ; then
      echo "Tables Locked"
      awk '/^TABLE LOCK table/{print $4}' "${file}" \
         | sort | uniq -c | sort -rn
   fi
   if grep 'has waited at' "${file}" > /dev/null ; then
      echo "Semaphore Waits"
      grep 'has waited at' "${file}" | cut -d' ' -f6-8 \
         | sort | uniq -c | sort -rn
   fi
   if grep 'reserved it in mode' "${file}" > /dev/null; then
      echo "Semaphore Holders"
      awk '/has reserved it in mode/{
         print substr($0, 1 + index($0, "("), index($0, ")") - index($0, "(") - 1);
      }' "${file}" | sort | uniq -c | sort -rn
   fi
   if grep -e 'Mutex at' -e 'lock on' "${file}" >/dev/null 2>&1; then
      echo "Mutexes/Locks Waited For"
      grep -e 'Mutex at' -e 'lock on' "${file}" | sed -e 's/^[XS]-//' -e 's/,.*$//' \
         | sort | uniq -c | sort -rn
   fi
}

# Summarizes per-database statistics for a bunch of different things: count of
# tables, views, etc.  $1 is the file name.  $2 is the database name; if none,
# then there should be multiple databases.
format_overall_db_stats () {
   local file="$1"
   local tmpfile="$PT_TMPDIR/format_overall_db_stats.tmp"

   [ -e "$file" ] || return

   echo
   # We keep counts of everything in an associative array keyed by db name, and
   # what it is.  The num_dbs counter is to ensure sort order is consistent when
   # we run the awk commands following this one.
   awk '
      BEGIN {
         # In case there is no USE statement in the file.
         db      = "{chosen}";
         num_dbs = 0;
      }
      /^USE `.*`;$/ {
         db = substr($2, 2, length($2) - 3);
         if ( db_seen[db]++ == 0 ) {
            dbs[num_dbs] = db;
            num_dbs++;
         }
      }
      /^CREATE TABLE/ {
         # Handle single-DB dumps, where there is no USE statement.
         if (num_dbs == 0) {
            num_dbs     = 1;
            db_seen[db] = 1;
            dbs[0]      = db;
         }
         counts[db ",tables"]++;
      }
      /CREATE ALGORITHM=/ {
         counts[db ",views"]++;
      }
      /03 CREATE.*03 PROCEDURE/ {
         counts[db ",sps"]++;
      }
      /03 CREATE.*03 FUNCTION/ {
         counts[db ",func"]++;
      }
      /03 CREATE.*03 TRIGGER/ {
         counts[db ",trg"]++;
      }
      /FOREIGN KEY/ {
         counts[db ",fk"]++;
      }
      /PARTITION BY/ {
         counts[db ",partn"]++;
      }
      END {
         mdb = length("Database");
         for ( i = 0; i < num_dbs; i++ ) {
            if ( length(dbs[i]) > mdb ) {
               mdb = length(dbs[i]);
            }
         }
         fmt = "  %-" mdb "s %6s %5s %3s %5s %5s %5s %5s\n";
         printf fmt, "Database", "Tables", "Views", "SPs", "Trigs", "Funcs", "FKs", "Partn";
         for ( i=0;i<num_dbs;i++ ) {
            db = dbs[i];
            printf fmt, db, counts[db ",tables"], counts[db ",views"], counts[db ",sps"], counts[db ",trg"], counts[db ",func"], counts[db ",fk"], counts[db ",partn"];
         }
      }
   ' "$file" > "$tmpfile"
   head -n2 "$tmpfile"
   tail -n +3 "$tmpfile" | sort

   echo
   # Now do the summary of engines per DB
   awk '
      BEGIN {
         # In case there is no USE statement in the file.
         db          = "{chosen}";
         num_dbs     = 0;
         num_engines = 0;
      }
      /^USE `.*`;$/ {
         db = substr($2, 2, length($2) - 3);
         if ( db_seen[db]++ == 0 ) {
            dbs[num_dbs] = db;
            num_dbs++;
         }
      }
      /^\) ENGINE=/ {
         # Handle single-DB dumps, where there is no USE statement.
         if (num_dbs == 0) {
            num_dbs     = 1;
            db_seen[db] = 1;
            dbs[0]      = db;
         }
         engine=substr($2, index($2, "=") + 1);
         if ( engine_seen[tolower(engine)]++ == 0 ) {
            engines[num_engines] = engine;
            num_engines++;
         }
         counts[db "," engine]++;
      }
      END {
         mdb = length("Database");
         for ( i=0;i<num_dbs;i++ ) {
            db = dbs[i];
            if ( length(db) > mdb ) {
               mdb = length(db);
            }
         }
         fmt = "  %-" mdb "s"
         printf fmt, "Database";
         for ( i=0;i<num_engines;i++ ) {
            engine = engines[i];
            fmts[engine] = " %" length(engine) "s";
            printf fmts[engine], engine;
         }
         print "";
         for ( i=0;i<num_dbs;i++ ) {
            db = dbs[i];
            printf fmt, db;
            for ( j=0;j<num_engines;j++ ) {
               engine = engines[j];
               printf fmts[engine], counts[db "," engine];
            }
            print "";
         }
      }
   ' "$file" > "$tmpfile"
   head -n1 "$tmpfile"
   tail -n +2 "$tmpfile" | sort

   echo
   # Now do the summary of index types per DB. Careful -- index is a reserved
   # word in awk.
   awk '
      BEGIN {
         # In case there is no USE statement in the file.
         db        = "{chosen}";
         num_dbs   = 0;
         num_idxes = 0;
      }
      /^USE `.*`;$/ {
         db = substr($2, 2, length($2) - 3);
         if ( db_seen[db]++ == 0 ) {
            dbs[num_dbs] = db;
            num_dbs++;
         }
      }
      /KEY/ {
         # Handle single-DB dumps, where there is no USE statement.
         if (num_dbs == 0) {
            num_dbs     = 1;
            db_seen[db] = 1;
            dbs[0]      = db;
         }
         idx="BTREE";
         if ( $0 ~ /SPATIAL/ ) {
            idx="SPATIAL";
         }
         if ( $0 ~ /FULLTEXT/ ) {
            idx="FULLTEXT";
         }
         if ( $0 ~ /USING RTREE/ ) {
            idx="RTREE";
         }
         if ( $0 ~ /USING HASH/ ) {
            idx="HASH";
         }
         if ( idx_seen[idx]++ == 0 ) {
            idxes[num_idxes] = idx;
            num_idxes++;
         }
         counts[db "," idx]++;
      }
      END {
         mdb = length("Database");
         for ( i=0;i<num_dbs;i++ ) {
            db = dbs[i];
            if ( length(db) > mdb ) {
               mdb = length(db);
            }
         }
         fmt = "  %-" mdb "s"
         printf fmt, "Database";
         for ( i=0;i<num_idxes;i++ ) {
            idx = idxes[i];
            fmts[idx] = " %" length(idx) "s";
            printf fmts[idx], idx;
         }
         print "";
         for ( i=0;i<num_dbs;i++ ) {
            db = dbs[i];
            printf fmt, db;
            for ( j=0;j<num_idxes;j++ ) {
               idx = idxes[j];
               printf fmts[idx], counts[db "," idx];
            }
            print "";
         }
      }
   ' "$file" > "$tmpfile"
   head -n1 "$tmpfile"
   tail -n +2 "$tmpfile" | sort

   echo
   # Now do the summary of datatypes per DB
   awk '
      BEGIN {
         # In case there is no USE statement in the file.
         db          = "{chosen}";
         num_dbs     = 0;
         num_types = 0;
      }
      /^USE `.*`;$/ {
         db = substr($2, 2, length($2) - 3);
         if ( db_seen[db]++ == 0 ) {
            dbs[num_dbs] = db;
            num_dbs++;
         }
      }
      /^  `/ {
         # Handle single-DB dumps, where there is no USE statement.
         if (num_dbs == 0) {
            num_dbs     = 1;
            db_seen[db] = 1;
            dbs[0]      = db;
         }
         str = $0;
         str = substr(str, index(str, "`") + 1);
         str = substr(str, index(str, "`") + 2);
         if ( index(str, " ") > 0 ) {
            str = substr(str, 1, index(str, " ") - 1);
         }
         if ( index(str, ",") > 0 ) {
            str = substr(str, 1, index(str, ",") - 1);
         }
         if ( index(str, "(") > 0 ) {
            str = substr(str, 1, index(str, "(") - 1);
         }
         type = str;
         if ( type_seen[type]++ == 0 ) {
            types[num_types] = type;
            num_types++;
         }
         counts[db "," type]++;
      }
      END {
         mdb = length("Database");
         for ( i=0;i<num_dbs;i++ ) {
            db = dbs[i];
            if ( length(db) > mdb ) {
               mdb = length(db);
            }
         }
         fmt = "  %-" mdb "s"
         mtlen = 0; # max type length
         for ( i=0;i<num_types;i++ ) {
            type = types[i];
            if ( length(type) > mtlen ) {
               mtlen = length(type);
            }
         }
         for ( i=1;i<=mtlen;i++ ) {
            printf "  %-" mdb "s", "";
            for ( j=0;j<num_types;j++ ) {
               type = types[j];
               if ( i > length(type) ) {
                  ch = " ";
               }
               else {
                  ch = substr(type, i, 1);
               }
               printf(" %3s", ch);
            }
            print "";
         }
         printf "  %-" mdb "s", "Database";
         for ( i=0;i<num_types;i++ ) {
            printf " %3s", "===";
         }
         print "";
         for ( i=0;i<num_dbs;i++ ) {
            db = dbs[i];
            printf fmt, db;
            for ( j=0;j<num_types;j++ ) {
               type = types[j];
               printf " %3s", counts[db "," type];
            }
            print "";
         }
      }
   ' "$file" > "$tmpfile"
   local hdr=$(grep -n Database "$tmpfile" | cut -d: -f1);
   head -n${hdr} "$tmpfile"
   tail -n +$((${hdr} + 1)) "$tmpfile" | sort
   echo
}

section_percona_server_features () {
   local file="$1"

   [ -e "$file" ] || return

   # Renamed to userstat in 5.5.10-20.1
   name_val "Table & Index Stats"   \
            "$(feat_on_renamed "$file" userstat_running userstat)"
   name_val "Multiple I/O Threads"  \
            "$(feat_on "$file" innodb_read_io_threads gt 1)"

   # Renamed to innodb_corrupt_table_action in 5.5.10-20.1
   name_val "Corruption Resilient"  \
            "$(feat_on_renamed "$file" innodb_pass_corrupt_table innodb_corrupt_table_action)"

   # Renamed to innodb_recovery_update_relay_log in 5.5.10-20.1
   name_val "Durable Replication"   \
            "$(feat_on_renamed "$file" innodb_overwrite_relay_log_info innodb_recovery_update_relay_log)"

   # Renamed to innodb_import_table_from_xtrabackup in 5.5.10-20.1
   name_val "Import InnoDB Tables"  \
            "$(feat_on_renamed "$file" innodb_expand_import innodb_import_table_from_xtrabackup)"

   # Renamed to innodb_buffer_pool_restore_at_startup in 5.5.10-20.1
   name_val "Fast Server Restarts"  \
            "$(feat_on_renamed "$file" innodb_auto_lru_dump innodb_buffer_pool_restore_at_startup)"
   
   name_val "Enhanced Logging"      \
            "$(feat_on "$file" log_slow_verbosity ne microtime)"
   name_val "Replica Perf Logging"  \
            "$(feat_on "$file" log_slow_slave_statements)"

   # Renamed to query_response_time_stats in 5.5
   name_val "Response Time Hist."   \
            "$(feat_on_renamed "$file" enable_query_response_time_stats query_response_time_stats)"

   # Renamed to innodb_adaptive_flushing_method in 5.5
   # This one is a bit more convulted than the rest because not only did it
   # change names, but also default values: none in 5.1, native in 5.5
   local smooth_flushing="$(feat_on_renamed "$file" innodb_adaptive_checkpoint innodb_adaptive_flushing_method)"
   if  [ "${smooth_flushing:-""}" != "Not Supported" ]; then
      if [ -n "$(get_var innodb_adaptive_checkpoint "$file")" ]; then
         smooth_flushing="$(feat_on "$file" "innodb_adaptive_checkpoint" ne none)"
      else
         smooth_flushing="$(feat_on "$file" "innodb_adaptive_flushing_method" ne native)"
      fi
   fi
   name_val "Smooth Flushing" "$smooth_flushing"
   
   name_val "HandlerSocket NoSQL"   \
            "$(feat_on "$file" handlersocket_port)"
   name_val "Fast Hash UDFs"   \
            "$(get_var "pt-summary-internal-FNV_64" "$file")"
}

section_myisam () {
   local variables_file="$1"
   local status_file="$2"

   [ -e "$variables_file" -a -e "$status_file" ] || return

   local buf_size="$(get_var key_buffer_size "$variables_file")"
   local blk_size="$(get_var key_cache_block_size "$variables_file")"
   local blk_unus="$(get_var Key_blocks_unused "$status_file")"
   local blk_unfl="$(get_var Key_blocks_not_flushed "$variables_file")"
   local unus=$((${blk_unus:-0} * ${blk_size:-0}))
   local unfl=$((${blk_unfl:-0} * ${blk_size:-0}))
   local used=$((${buf_size:-0} - ${unus}))

   name_val "Key Cache" "$(shorten ${buf_size} 1)"
   name_val "Pct Used" "$(fuzzy_pct ${used} ${buf_size})"
   name_val "Unflushed" "$(fuzzy_pct ${unfl} ${buf_size})"
}

section_innodb () {
   local variables_file="$1"
   local status_file="$2"

   [ -e "$variables_file" -a -e "$status_file" ] || return

   # XXX TODO I don't think this is working right.
   # XXX TODO Should it use data from information_schema.plugins too?
   local version=$(get_var innodb_version "$variables_file")
   name_val Version ${version:-default}

   local bp_size="$(get_var innodb_buffer_pool_size "$variables_file")"
   name_val "Buffer Pool Size" "$(shorten "${bp_size:-0}" 1)"

   local bp_pags="$(get_var Innodb_buffer_pool_pages_total "$status_file")"
   local bp_free="$(get_var Innodb_buffer_pool_pages_free "$status_file")"
   local bp_dirt="$(get_var Innodb_buffer_pool_pages_dirty "$status_file")"
   local bp_fill=$((${bp_pags} - ${bp_free}))
   name_val "Buffer Pool Fill"   "$(fuzzy_pct ${bp_fill} ${bp_pags})"
   name_val "Buffer Pool Dirty"  "$(fuzzy_pct ${bp_dirt} ${bp_pags})"

   name_val "File Per Table"      $(get_var innodb_file_per_table "$variables_file")
   name_val "Page Size"           $(shorten $(get_var Innodb_page_size "$status_file") 0)

   local log_size="$(get_var innodb_log_file_size "$variables_file")"
   local log_file="$(get_var innodb_log_files_in_group "$variables_file")"
   local log_total=$(awk "BEGIN {printf \"%.2f\n\", ${log_size}*${log_file}}" )
   name_val "Log File Size"       \
            "${log_file} * $(shorten ${log_size} 1) = $(shorten ${log_total} 1)"
   name_val "Log Buffer Size"     \
            "$(shorten $(get_var innodb_log_buffer_size "$variables_file") 0)"
   name_val "Flush Method"        \
            "$(get_var innodb_flush_method "$variables_file")"
   name_val "Flush Log At Commit" \
            "$(get_var innodb_flush_log_at_trx_commit "$variables_file")"
   name_val "XA Support"          \
            "$(get_var innodb_support_xa "$variables_file")"
   name_val "Checksums"           \
            "$(get_var innodb_checksums "$variables_file")"
   name_val "Doublewrite"         \
            "$(get_var innodb_doublewrite "$variables_file")"
   name_val "R/W I/O Threads"     \
            "$(get_var innodb_read_io_threads "$variables_file") $(get_var innodb_write_io_threads "$variables_file")"
   name_val "I/O Capacity"        \
            "$(get_var innodb_io_capacity "$variables_file")"
   name_val "Thread Concurrency"  \
            "$(get_var innodb_thread_concurrency "$variables_file")"
   name_val "Concurrency Tickets" \
            "$(get_var innodb_concurrency_tickets "$variables_file")"
   name_val "Commit Concurrency"  \
            "$(get_var innodb_commit_concurrency "$variables_file")"
   name_val "Txn Isolation Level" \
            "$(get_var tx_isolation "$variables_file")"
   name_val "Adaptive Flushing"   \
            "$(get_var innodb_adaptive_flushing "$variables_file")"
   name_val "Adaptive Checkpoint" \
            "$(get_var innodb_adaptive_checkpoint "$variables_file")"
}


section_noteworthy_variables () {
   local file="$1"

   [ -e "$file" ] || return

   name_val "Auto-Inc Incr/Offset" "$(get_var auto_increment_increment "$file")/$(get_var auto_increment_offset "$file")"
   for v in \
      default_storage_engine flush_time init_connect init_file sql_mode;
   do
      name_val "${v}" "$(get_var ${v} "$file")"
   done
   for v in \
      join_buffer_size sort_buffer_size read_buffer_size read_rnd_buffer_size \
      bulk_insert_buffer max_heap_table_size tmp_table_size \
      max_allowed_packet thread_stack;
   do
      name_val "${v}" "$(shorten $(get_var ${v} "$file") 0)"
   done
   for v in log log_error log_warnings log_slow_queries \
         log_queries_not_using_indexes log_slave_updates;
   do
      name_val "${v}" "$(get_var ${v} "$file")"
   done
}

#
# Formats and outputs the semisyncronious replication-related variables
#
_semi_sync_stats_for () {
   local target="$1"
   local file="$2"

   [ -e "$file" ] || return

   local semisync_status="$(get_var "Rpl_semi_sync_${target}_status" "${file}" )"
   local semisync_trace="$(get_var "rpl_semi_sync_${target}_trace_level" "${file}")"

   local trace_extra=""
   if [ -n "${semisync_trace}" ]; then
      if [ $semisync_trace -eq 1 ]; then
         trace_extra="general (for example, time function failures) "
      elif [ $semisync_trace -eq 16 ]; then
         trace_extra="detail (more verbose information) "
      elif [ $semisync_trace -eq 32 ]; then
         trace_extra="net wait (more information about network waits)"
      elif [ $semisync_trace -eq 64 ]; then
         trace_extra="function (information about function entry and exit)"
      else
         trace_extra="Unknown setting"
      fi
   fi
   
   name_val "${target} semisync status" "${semisync_status}"
   name_val "${target} trace level" "${semisync_trace}, ${trace_extra}"

   if [ "${target}" = "master" ]; then
      name_val "${target} timeout in milliseconds" \
               "$(get_var "rpl_semi_sync_${target}_timeout" "${file}")"
      name_val "${target} waits for slaves"        \
               "$(get_var "rpl_semi_sync_${target}_wait_no_slave" "${file}")"

      _d "Prepend Rpl_semi_sync_master_ to the following"
      for v in                                              \
         clients net_avg_wait_time net_wait_time net_waits  \
         no_times no_tx timefunc_failures tx_avg_wait_time  \
         tx_wait_time tx_waits wait_pos_backtraverse        \
         wait_sessions yes_tx;
      do
         name_val "${target} ${v}" \
                  "$( get_var "Rpl_semi_sync_master_${v}" "${file}" )"
      done
   fi
}

# Make a pattern of things we want to omit because they aren't
# counters, they are gauges (in RRDTool terminology).  Gauges are shown
# elsewhere in the output.
noncounters_pattern () {
   local noncounters_pattern=""

   for var in Compression Delayed_insert_threads Innodb_buffer_pool_pages_data \
      Innodb_buffer_pool_pages_dirty Innodb_buffer_pool_pages_free \
      Innodb_buffer_pool_pages_latched Innodb_buffer_pool_pages_misc \
      Innodb_buffer_pool_pages_total Innodb_data_pending_fsyncs \
      Innodb_data_pending_reads Innodb_data_pending_writes \
      Innodb_os_log_pending_fsyncs Innodb_os_log_pending_writes \
      Innodb_page_size Innodb_row_lock_current_waits Innodb_row_lock_time_avg \
      Innodb_row_lock_time_max Key_blocks_not_flushed Key_blocks_unused \
      Key_blocks_used Last_query_cost Max_used_connections Ndb_cluster_node_id \
      Ndb_config_from_host Ndb_config_from_port Ndb_number_of_data_nodes \
      Not_flushed_delayed_rows Open_files Open_streams Open_tables \
      Prepared_stmt_count Qcache_free_blocks Qcache_free_memory \
      Qcache_queries_in_cache Qcache_total_blocks Rpl_status \
      Slave_open_temp_tables Slave_running Ssl_cipher Ssl_cipher_list \
      Ssl_ctx_verify_depth Ssl_ctx_verify_mode Ssl_default_timeout \
      Ssl_session_cache_mode Ssl_session_cache_size Ssl_verify_depth \
      Ssl_verify_mode Ssl_version Tc_log_max_pages_used Tc_log_page_size \
      Threads_cached Threads_connected Threads_running \
      Uptime_since_flush_status;
   do
      if [ -z "${noncounters_pattern}" ]; then
         noncounters_pattern="${var}"
      else
         noncounters_pattern="${noncounters_pattern}\|${var}"
      fi
   done
   echo $noncounters_pattern
}

section_mysqld () {
   local executables_file="$1"
   local variables_file="$2"

   [ -e "$executables_file" -a -e "$variables_file" ] || return

   section "MySQL Executable"
   local i=1;
   while read executable; do
      name_val "Path to executable" "$executable"
      name_val "Has symbols" "$( get_var "pt-summary-internal-mysqld_executable_${i}" "$variables_file" )"
      i=$(($i + 1))
   done < "$executables_file"
}

section_mysql_files () {
   local variables_file="$1"

   section "MySQL Files"
   for file_name in pid_file slow_query_log_file general_log_file log_error; do
      local file="$(get_var "${file_name}" "$variables_file")"
      local name_out="$(echo "$file_name" | sed 'y/[a-z]/[A-Z]/')"
      if [ -e "${file}" ]; then
         name_val "$name_out" "$file"
         name_val "${name_out} Size" "$(du "$file" | awk '{print $1}')"
      else
         name_val "$name_out" "(does not exist)"
      fi
   done
}

section_percona_xtradb_cluster () {
   local mysql_var="$1"
   local mysql_status="$2"

   name_val "Cluster Name"    "$(get_var "wsrep_cluster_name" "$mysql_var")"
   name_val "Cluster Address" "$(get_var "wsrep_cluster_address" "$mysql_var")"
   name_val "Cluster Size"    "$(get_var "wsrep_cluster_size" "$mysql_status")"
   name_val "Cluster Nodes"   "$(get_var "wsrep_incoming_addresses" "$mysql_status")"

   name_val "Node Name"       "$(get_var "wsrep_node_name" "$mysql_var")"
   name_val "Node Status"     "$(get_var "wsrep_cluster_status" "$mysql_status")"

   name_val "SST Method"      "$(get_var "wsrep_sst_method" "$mysql_var")"
   name_val "Slave Threads"   "$(get_var "wsrep_slave_threads" "$mysql_var")"
   
   name_val "Ignore Split Brain" "$( parse_wsrep_provider_options "pc.ignore_sb" "$mysql_var" )"
   name_val "Ignore Quorum" "$( parse_wsrep_provider_options "pc.ignore_quorum" "$mysql_var" )"
   
   name_val "gcache Size"      "$( parse_wsrep_provider_options "gcache.size" "$mysql_var" )"
   name_val "gcache Directory" "$( parse_wsrep_provider_options "gcache.dir" "$mysql_var" )"
   name_val "gcache Name"      "$( parse_wsrep_provider_options "gcache.name" "$mysql_var" )"
}

parse_wsrep_provider_options () {
   local looking_for="$1"
   local mysql_var_file="$2"

   grep wsrep_provider_options "$mysql_var_file" \
   | perl -Mstrict -le '
      my $provider_opts = scalar(<STDIN>);
      my $looking_for   = $ARGV[0];
      my %opts          = $provider_opts =~ /(\S+)\s*=\s*(\S*)(?:;|$)/g;
      print $opts{$looking_for};
   ' "$looking_for"
}

report_mysql_summary () {
   local dir="$1"

   # Field width for name_val
   local NAME_VAL_LEN=25

   # ########################################################################
   # Header for the whole thing, table of discovered instances
   # ########################################################################

   section "Percona Toolkit MySQL Summary Report"
   name_val "System time" "`date -u +'%F %T UTC'` (local TZ: `date +'%Z %z'`)"
   section "Instances"
   parse_mysqld_instances "$dir/mysqld-instances" "$dir/mysql-variables"

   section_mysqld "$dir/mysqld-executables" "$dir/mysql-variables"

   # ########################################################################
   # General date, hostname, etc
   # ########################################################################
   local user="$(get_var "pt-summary-internal-user" "$dir/mysql-variables")"
   local port="$(get_var port "$dir/mysql-variables")"
   local now="$(get_var "pt-summary-internal-now" "$dir/mysql-variables")"
   section "Report On Port ${port}"
   name_val User "${user}"
   name_val Time "${now} ($(get_mysql_timezone "$dir/mysql-variables"))"
   name_val Hostname "$(get_var hostname "$dir/mysql-variables")"
   get_mysql_version "$dir/mysql-variables"

   local uptime="$(get_var Uptime "$dir/mysql-status")"
   local current_time="$(get_var "pt-summary-internal-current_time" "$dir/mysql-variables")"
   name_val Started "$(get_mysql_uptime "${uptime}" "${current_time}")"

   local num_dbs="$(grep -c . "$dir/mysql-databases")"
   name_val Databases "${num_dbs}"
   name_val Datadir "$(get_var datadir "$dir/mysql-variables")"

   local fuzz_procs=$(fuzz $(get_var Threads_connected "$dir/mysql-status"))
   local fuzz_procr=$(fuzz $(get_var Threads_running "$dir/mysql-status"))
   name_val Processes "${fuzz_procs} connected, ${fuzz_procr} running"

   local slave=""
   if [ -s "$dir/mysql-slave" ]; then slave=""; else slave="not "; fi
   local slavecount=$(grep -c 'Binlog Dump' "$dir/mysql-processlist")
   name_val Replication "Is ${slave}a slave, has ${slavecount} slaves connected"


   # TODO move this into a section with other files: error log, slow log and
   # show the sizes
   #   section_mysql_files "$dir/mysql-variables"
   local pid_file="$(get_var "pid_file" "$dir/mysql-variables")"
   local PID_EXISTS=""
   if [ "$( get_var "pt-summary-internal-pid_file_exists" "$dir/mysql-variables" )" ]; then
      PID_EXISTS="(exists)"
   else
      PID_EXISTS="(does not exist)"
   fi
   name_val Pidfile "${pid_file} ${PID_EXISTS}"

   # ########################################################################
   # Processlist, sliced several different ways
   # ########################################################################
   section "Processlist"
   summarize_processlist "$dir/mysql-processlist"

   # ########################################################################
   # Queries and query plans
   # ########################################################################
   section "Status Counters (Wait ${OPT_SLEEP} Seconds)"
   # Wait for the child that was forked during collection.
   wait
   local noncounters_pattern="$(noncounters_pattern)"
   format_status_variables "$dir/mysql-status-defer" | grep -v "${noncounters_pattern}"

   # ########################################################################
   # Table cache
   # ########################################################################
   section "Table cache"
   local open_tables=$(get_var "Open_tables" "$dir/mysql-status")
   local table_cache=$(get_table_cache "$dir/mysql-variables")
   name_val Size  $table_cache
   name_val Usage "$(fuzzy_pct ${open_tables} ${table_cache})"

   # ########################################################################
   # Percona Server features
   # ########################################################################
   section "Key Percona Server features"
   section_percona_server_features "$dir/mysql-variables"

   # ########################################################################
   # Percona XtraDB Cluster data
   # ########################################################################
   section "Percona XtraDB Cluster"
   local has_wsrep="$(get_var "wsrep_on" "$dir/mysql-variables")"
   if [ -n "${has_wsrep:-""}" ]; then
      local wsrep_on="$(feat_on "$dir/mysql-variables" "wsrep_on")"
      if [ "${wsrep_on:-""}" = "Enabled" ]; then
         section_percona_xtradb_cluster "$dir/mysql-variables" "$dir/mysql-status"
      else
         name_val "wsrep_on" "OFF"
      fi
   fi

   # ########################################################################
   # Plugins
   # ########################################################################
   # TODO: what would be good is to show nonstandard plugins here.
   section "Plugins"
   name_val "InnoDB compression" "$(get_plugin_status "$dir/mysql-plugins" "INNODB_CMP")"

   # ########################################################################
   # Query cache
   # ########################################################################
   if [ "$(get_var have_query_cache "$dir/mysql-variables")" ]; then
      section "Query cache"
      local query_cache_size=$(get_var query_cache_size "$dir/mysql-variables")
      local used=$(( ${query_cache_size} - $(get_var Qcache_free_memory "$dir/mysql-status") ))
      local hrat=$(fuzzy_pct $(get_var Qcache_hits "$dir/mysql-status") $(get_var Qcache_inserts "$dir/mysql-status"))
      name_val query_cache_type $(get_var query_cache_type "$dir/mysql-variables")
      name_val Size "$(shorten ${query_cache_size} 1)"
      name_val Usage "$(fuzzy_pct ${used} ${query_cache_size})"
      name_val HitToInsertRatio "${hrat}"
   fi

   local semisync_enabled_master="$(get_var "rpl_semi_sync_master_enabled" "$dir/mysql-variables")"
   if [ -n "${semisync_enabled_master}" ]; then
      section "Semisynchronous Replication"
      if [ "$semisync_enabled_master" = "OFF" -o "$semisync_enabled_master" = "0" -o -z "$semisync_enabled_master" ]; then
         name_val "Master" "Disabled"
      else
         _semi_sync_stats_for "master" "$dir/mysql-variables"
      fi
      local semisync_enabled_slave="$(get_var rpl_semi_sync_slave_enabled "$dir/mysql-variables")"
      if    [ "$semisync_enabled_slave" = "OFF" -o "$semisync_enabled_slave" = "0" -o -z "$semisync_enabled_slave" ]; then
         name_val "Slave" "Disabled"
      else
         _semi_sync_stats_for "slave" "$dir/mysql-variables"
      fi
   fi

   # ########################################################################
   # Schema, databases, data type, other analysis.
   # ########################################################################
   section "Schema"
   # Test the result by checking the file, not by the exit status, because we
   # might get partway through and then die, and the info is worth analyzing
   # anyway.
   if [ -s "$dir/mysqldump" ] \
      && grep 'CREATE TABLE' "$dir/mysqldump" >/dev/null 2>&1; then
         format_overall_db_stats "$dir/mysqldump"
   elif [ ! -e "$dir/mysqldump" -a "$OPT_READ_SAMPLES" ]; then
      echo "Skipping schema analysis because --read-samples $dir/mysqldump " \
         "does not exist"
   elif [ -z "$OPT_DATABASES" -a -z "$OPT_ALL_DATABASES" ]; then
      echo "Specify --databases or --all-databases to dump and summarize schemas"
   else
      echo "Skipping schema analysis due to apparent error in dump file"
   fi

   # ########################################################################
   # Noteworthy Technologies
   # ########################################################################
   section "Noteworthy Technologies"
   if [ -s "$dir/mysqldump" ]; then
      if grep FULLTEXT "$dir/mysqldump" > /dev/null; then
         name_val "Full Text Indexing" "Yes"
      else
         name_val "Full Text Indexing" "No"
      fi
      if grep 'GEOMETRY\|POINT\|LINESTRING\|POLYGON' "$dir/mysqldump" > /dev/null; then
         name_val "Geospatial Types" "Yes"
      else
         name_val "Geospatial Types" "No"
      fi
      if grep 'FOREIGN KEY' "$dir/mysqldump" > /dev/null; then
         name_val "Foreign Keys" "Yes"
      else
         name_val "Foreign Keys" "No"
      fi
      if grep 'PARTITION BY' "$dir/mysqldump" > /dev/null; then
         name_val "Partitioning" "Yes"
      else
         name_val "Partitioning" "No"
      fi
      if grep -e 'ENGINE=InnoDB.*ROW_FORMAT' \
         -e 'ENGINE=InnoDB.*KEY_BLOCK_SIZE' "$dir/mysqldump" > /dev/null; then
         name_val "InnoDB Compression" "Yes"
      else
         name_val "InnoDB Compression" "No"
      fi
   fi
   local ssl="$(get_var Ssl_accepts "$dir/mysql-status")"
   if [ -n "$ssl" -a "${ssl:-0}" -gt 0 ]; then
      name_val "SSL" "Yes"
   else
      name_val "SSL" "No"
   fi
   local lock_tables="$(get_var Com_lock_tables "$dir/mysql-status")"
   if [ -n "$lock_tables" -a "${lock_tables:-0}" -gt 0 ]; then
      name_val "Explicit LOCK TABLES" "Yes"
   else
      name_val "Explicit LOCK TABLES" "No"
   fi
   local delayed_insert="$(get_var Delayed_writes "$dir/mysql-status")"
   if [ -n "$delayed_insert" -a "${delayed_insert:-0}" -gt 0 ]; then
      name_val "Delayed Insert" "Yes"
   else
      name_val "Delayed Insert" "No"
   fi
   local xat="$(get_var Com_xa_start "$dir/mysql-status")"
   if [ -n "$xat" -a "${xat:-0}" -gt 0 ]; then
      name_val "XA Transactions" "Yes"
   else
      name_val "XA Transactions" "No"
   fi
   local ndb_cluster="$(get_var "Ndb_cluster_node_id" "$dir/mysql-status")"
   if [ -n "$ndb_cluster" -a "${ndb_cluster:-0}" -gt 0 ]; then
      name_val "NDB Cluster" "Yes"
   else
      name_val "NDB Cluster" "No"
   fi
   local prep=$(( $(get_var "Com_stmt_prepare" "$dir/mysql-status") + $(get_var "Com_prepare_sql" "$dir/mysql-status") ))
   if [ "${prep}" -gt 0 ]; then
      name_val "Prepared Statements" "Yes"
   else
      name_val "Prepared Statements" "No"
   fi
   local prep_count="$(get_var Prepared_stmt_count "$dir/mysql-status")"
   if [ "${prep_count}" ]; then
      name_val "Prepared statement count" "${prep_count}"
   fi

   # ########################################################################
   # InnoDB
   # ########################################################################
   section "InnoDB"
   local have_innodb="$(get_var "have_innodb" "$dir/mysql-variables")"
   if [ "${have_innodb}" = "YES" ]; then
      section_innodb "$dir/mysql-variables" "$dir/mysql-status"

      if [ -s "$dir/innodb-status" ]; then
         format_innodb_status "$dir/innodb-status"
      fi
   fi

   # ########################################################################
   # MyISAM
   # ########################################################################
   section "MyISAM"
   section_myisam "$dir/mysql-variables" "$dir/mysql-status"

   # ########################################################################
   # Users & Security
   # ########################################################################
   section "Security"
   local users="$( format_users "$dir/mysql-users" )"
   name_val "Users" "${users}"
   name_val "Old Passwords" "$(get_var old_passwords "$dir/mysql-variables")"

   # ########################################################################
   # Binary Logging
   # ########################################################################
   section "Binary Logging"

   if    [ -s "$dir/mysql-master-logs" ] \
      || [ -s "$dir/mysql-master-status" ]; then
      summarize_binlogs "$dir/mysql-master-logs"
      local format="$(get_var binlog_format "$dir/mysql-variables")"
      name_val binlog_format "${format:-STATEMENT}"
      name_val expire_logs_days "$(get_var expire_logs_days "$dir/mysql-variables")"
      name_val sync_binlog "$(get_var sync_binlog "$dir/mysql-variables")"
      name_val server_id "$(get_var server_id "$dir/mysql-variables")"
      format_binlog_filters "$dir/mysql-master-status"
   fi

# Replication: seconds behind, running, filters, skip_slave_start, skip_errors,
# read_only, temp tables open, slave_net_timeout, slave_exec_mode

   # ########################################################################
   # Interesting things that you just ought to know about.
   # ########################################################################
   section "Noteworthy Variables"
   section_noteworthy_variables "$dir/mysql-variables"

   # ########################################################################
   # If there is a my.cnf in a standard location, see if we can pretty-print it.
   # ########################################################################
   section "Configuration File"
   local cnf_file="$(get_var "pt-summary-internal-Config_File_path" "$dir/mysql-variables")"

   if [ -n "${cnf_file}" ]; then
      name_val "Config File" "${cnf_file}"
      pretty_print_cnf_file "$dir/mysql-config-file"
   else
      name_val "Config File" "Cannot autodetect or find, giving up"
   fi

   # Make sure that we signal the end of the tool's output.
   section "The End"
}

# ###########################################################################
# End report_mysql_info package
# ###########################################################################
