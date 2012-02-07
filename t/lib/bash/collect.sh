#!/usr/bin/env bash

TESTS=20

TMPFILE="$TEST_TMPDIR/parse-opts-output"
TMPDIR="$TEST_TMPDIR"
PATH="$PATH:$PERCONA_TOOLKIT_SANDBOX/bin"
TOOL="pt-stalk"

mkdir "$TMPDIR/collect" 2>/dev/null

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/parse_options.sh"
source "$LIB_DIR/safeguards.sh"
source "$LIB_DIR/alt_cmds.sh"
source "$LIB_DIR/collect.sh"

parse_options "$BIN_DIR/pt-stalk" --run-time 1 -- --defaults-file=/tmp/12345/my.sandbox.cnf

# Prefix (with path) for the collect files.
local p="$TMPDIR/collect/2011_12_05"

# Default collect, no extras like gdb, tcpdump, etc.
collect "$TMPDIR/collect" "2011_12_05" > $p-output 2>&1

# Even if this system doesn't have all the cmds, collect should still
# have created some files for cmds that (hopefully) all systems have.
ls -1 $TMPDIR/collect | sort > $TMPDIR/collect-files

# If this system has /proc, then some files should be collected.
# Else, those files should not exist.
if [ -f /proc/diskstats ]; then
   cmd_ok \
      "grep -q '[0-9]' $TMPDIR/collect/2011_12_05-diskstats" \
      "/proc/diskstats"
else
   test -f $TMPDIR/collect/2011_12_05-diskstats
   is "$?" "1" "No /proc/diskstats"
fi

cmd_ok \
   "grep -q '\-hostname\$' $TMPDIR/collect-files" \
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

if [[ "$SANDBOX_VERSION" > "5.0" ]]; then
   cmd_ok \
      "grep -q 'Status information:' $p-log_error" \
      "debug"
else
   is "1" "1" "SKIP Can't determine MySQL 5.0 error log"
fi

cmd_ok \
   "grep -q 'COMMAND[ ]\+PID[ ]\+USER' $p-lsof" \
   "lsof"

cmd_ok \
   "grep -q 'buf0buf.c' $p-mutex-status1" \
   "mutex-status1"

cmd_ok \
   "grep -q 'buf0buf.c' $p-mutex-status2" \
   "mutex-status2"

cmd_ok \
   "grep -q '^| Uptime' $p-mysqladmin" \
   "mysqladmin ext"

cmd_ok \
   "grep -qP 'Database\tTable\tIn_use' $p-opentables1" \
   "opentables1"

cmd_ok \
   "grep -qP 'Database\tTable\t\In_use' $p-opentables2" \
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

local iters=$(cat $p-df | grep -c '^TS ')
is "$iters" "1" "1 iteration/1s run time"

empty_files=0
for file in $p-*; do
   if ! [ -s $file ]; then
      empty_files=1
      break
   fi
   if [ -z "$(grep -v '^TS ' --max-count 1 $file)" ]; then
      empty_files=1
      break
   fi
done

is "$empty_files" "0" "No empty files"

# ###########################################################################
# Try longer run time.
# ###########################################################################

parse_options "$BIN_DIR/pt-stalk" --run-time 2 -- --defaults-file=/tmp/12345/my.sandbox.cnf

rm $TMPDIR/collect/*

collect "$TMPDIR/collect" "2011_12_05" > $p-output 2>&1

local iters=$(cat $p-df | grep -c '^TS ')
is "$iters" "2" "2 iteration/2s run time"

# ############################################################################
# Done
# ############################################################################
