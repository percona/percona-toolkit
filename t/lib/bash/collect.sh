#!/usr/bin/env bash

plan 22

TMPFILE="$TEST_PT_TMPDIR/parse-opts-output"
PT_TMPDIR="$TEST_PT_TMPDIR"
PATH="$PATH:$PERCONA_TOOLKIT_SANDBOX/bin"
TOOL="pt-stalk"

mkdir "$PT_TMPDIR/collect" 2>/dev/null

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/subshell.sh"
source "$LIB_DIR/parse_options.sh"
source "$LIB_DIR/safeguards.sh"
source "$LIB_DIR/alt_cmds.sh"
source "$LIB_DIR/collect.sh"

# We need flush tables, otherwise we won't have stable results for opentables tests
CMD_MYSQL="$(_which mysql)"
$CMD_MYSQL --defaults-file=/tmp/12345/my.sandbox.cnf -ss -e 'FLUSH TABLES'

parse_options "$BIN_DIR/pt-stalk" --run-time 1 -- --defaults-file=/tmp/12345/my.sandbox.cnf

# Prefix (with path) for the collect files.
p="$PT_TMPDIR/collect/2011_12_05"

# Default collect, no extras like gdb, tcpdump, etc.
collect "$PT_TMPDIR/collect" "2011_12_05" > $p-output 2>&1

wait_for_files "$p-hostname" "$p-opentables2" "$p-variables" "$p-df" "$p-innodbstatus2"

cat "$p-opentables2" > /tmp/collect.test

# Even if this system doesn't have all the cmds, collect should still
# have created some files for cmds that (hopefully) all systems have.
ls -1 $PT_TMPDIR/collect | sort > $PT_TMPDIR/collect-files

# If this system has /proc, then some files should be collected.
# Else, those files should not exist.
if [ -f /proc/diskstats ]; then
   wait_for_files "$p-diskstats"
   cmd_ok \
      "grep -q '[0-9]' $p-diskstats" \
      "/proc/diskstats"
else
   test -f $PT_TMPDIR/collect/$p-diskstats
   is "$?" "1" "No /proc/diskstats"
fi

cmd_ok \
   "grep -q '\-hostname\$' $PT_TMPDIR/collect-files" \
   "Collected hostname"

cmd_ok \
   "grep -q 'Avail' $p-df" \
   "df"

# hostname is the last thing collected, so if it's ok,
# then the sub reached its end.
is \
   "`cat $p-hostname`" \
   "`hostname`" \
   "hostname"

cmd_ok \
   "grep -q -i 'buffer pool' $p-innodbstatus1" \
   "innodbstatus1"

cmd_ok \
   "grep -q -i 'buffer pool' $p-innodbstatus2" \
   "innodbstatus2"

cmd_ok \
   "grep -q 'error log seems to be .*/mysqld.log' $p-output" \
   "Finds MySQL error log"

if [ "$(which lsof 2>/dev/null)" ]; then
   wait_for_files "$p-lsof"
   cmd_ok \
      "grep -q 'COMMAND[ ]\+PID[ ]\+USER' $p-lsof" \
      "lsof"
else
   is "1" "1" "SKIP lsof not in PATH"
fi

cmd_ok \
   "grep -q -e OS_waits -e Type $p-mutex-status1" \
   "mutex-status1"

cmd_ok \
   "grep -q -e OS_waits -e Type $p-mutex-status2" \
   "mutex-status2"

cmd_ok \
   "grep -q '^| Uptime' $p-mysqladmin" \
   "mysqladmin ext"

cmd_ok \
   "grep -qP 'Database\tTable\tIn_use' $p-opentables1" \
   "opentables1"

cmd_ok \
   "grep -qP 'Database\tTable\tIn_use' $p-opentables2" \
   "opentables2"

cmd_ok \
   "grep -q '1. row' $p-processlist" \
   "processlist"

cmd_ok \
   "grep -q 'mysqld' $p-ps" \
   "ps"

cmd_ok \
   "grep -qP '^wait_timeout\t\d' $p-variables" \
   "variables"

iters=$(cat $p-df | grep -c '^TS ')
is "$iters" "1" "1 iteration/1s run time"

empty_files=0
for file in $p-*; do
   if ! [ -s $file ]; then
      empty_files=1
      break
   fi
   # We need additional check here in case if first match
   # is empty string.
   if [ 0 -eq "$(grep -vc '^TS ' --max-count 1 $file)" ] || 
	   [ 0 -eq "$(grep -vc '^$' --max-count 1 $file)" ]; then
      empty_files=1
      break
   fi
done

is "$empty_files" "0" "No empty files"

# ###########################################################################
# Debug option for mysqladmin is not default now, we will test it separately.
# ###########################################################################

#Skipping until PT-2242 is fixed
if false; then
   parse_options "$BIN_DIR/pt-stalk" --run-time 2 -- --defaults-file=/tmp/12345/my.sandbox.cnf

   rm $PT_TMPDIR/collect/*

   # Prefix (with path) for the collect files.
   p="$PT_TMPDIR/collect/2011_12_05"

   CMD_MYSQLADMIN="mysqladmin debug"
   # Default collect, no extras like gdb, tcpdump, etc.
   collect "$PT_TMPDIR/collect" "2011_12_05" > $p-output 2>&1

   wait_for_files "$p-hostname" "$p-opentables2" "$p-variables" "$p-df" "$p-innodbstatus2"

   if [[ "$SANDBOX_VERSION" > "5.0" ]]; then
      wait_for_files "$p-log_error"
      cmd_ok \
         "grep -qE 'Memory status|Open streams|Begin safemalloc' $p-log_error" \
         "debug"
   else
      is "1" "1" "SKIP Can't determine MySQL 5.0 error log"
   fi
else
   is "1" "1" "SKIP until PT-2242 is fixed"
fi

# ###########################################################################
# Try longer run time.
# ###########################################################################

parse_options "$BIN_DIR/pt-stalk" --run-time 3 -- --defaults-file=/tmp/12345/my.sandbox.cnf

rm $PT_TMPDIR/collect/*

fake_opcontrol="$PT_TMPDIR/collect/fake_opcontrol"
fake_out="$PT_TMPDIR/collect/pt-faked-opcontrol-out"
cat <<FAKE_EXEC > "$fake_opcontrol"
#!/bin/sh

echo "Faked opcontrol: \$@" > "$fake_out"

exit 1

FAKE_EXEC

chmod +x "$fake_opcontrol"

CMD_OPCONTROL="$fake_opcontrol"
OPT_COLLECT_OPROFILE=1
collect "$PT_TMPDIR/collect" "2011_12_05" > $p-output 2>&1
CMD_OPCONTROL=""
OPT_COLLECT_OPROFILE=""

iters=$(cat $p-df | grep -c '^TS ')
# We need to adjust result on slow machines
if [ $iters -eq 2 ]; then
   iters=3;
fi
is "$iters" "3" "2 or 3 iteration/3s run time"

is \
   "$(cat "$fake_out")" \
   "Faked opcontrol: --init" \
   "Bug 986847: Can manually set which commands pt-stalk uses"

if [ -f "$p-vmstat" ]; then
   n=$(awk '/[ ]*[0-9]/ { n += 1 } END { print n }' "$p-vmstat")
   is \
      "$n" \
      "3" \
      "vmstat runs for --run-time seconds (bug 955860)"
else
   is "1" "1" "SKIP vmstat not installed"
fi

# ############################################################################
# Done
# ############################################################################
