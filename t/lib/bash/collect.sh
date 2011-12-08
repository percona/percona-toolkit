#!/usr/bin/env bash

TESTS=18

TMPFILE="$TEST_TMPDIR/parse-opts-output"
TMPDIR="$TEST_TMPDIR"
PATH="$PATH:$PERCONA_TOOLKIT_SANDBOX/bin"

mkdir "$TMPDIR/collect" 2>/dev/null

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/parse_options.sh"
source "$LIB_DIR/safeguards.sh"
source "$LIB_DIR/alt_cmds.sh"
source "$LIB_DIR/collect.sh"

parse_options "$T_LIB_DIR/samples/bash/po002.sh" --run-time 1 -- --defaults-file=/tmp/12345/my.sandbox.cnf

# Prefix (with path) for the collect files.
local p="$TMPDIR/collect/2011_12_05"

# Default collect, no extras like gdb, tcpdump, etc.
collect "$TMPDIR/collect" "2011_12_05" > $p-output 2>&1

# Even if this system doesn't have all the cmds, collect should still
# create all the default files.
ls -1 $TMPDIR/collect | sort > $TMPDIR/collect-files
no_diff \
   $TMPDIR/collect-files \
   $T_LIB_DIR/samples/bash/collect001.txt \
   "Default collect files"

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
   "grep -q 'error log seems to be /tmp/12345/data/mysqld.log' $p-output" \
   "Finds MySQL error log"

cmd_ok \
   "grep -q 'Status information:' $p-log_error" \
   "debug"

cmd_ok \
   "grep -q 'COMMAND[ ]\+PID[ ]\+USER' $p-lsof" \
   "lsof"

cmd_ok \
   "grep -q 'buf/buf0buf.c' $p-mutex-status1" \
   "mutex-status1"

cmd_ok \
   "grep -q 'buf/buf0buf.c' $p-mutex-status2" \
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
   "grep -qP '^warning_count\t\d' $p-variables" \
   "variables"

local iters=$(cat $p-df | grep -c '^TS ')
is "$iters" "1" "1 iteration/1s run time"

# ###########################################################################
# Try longer run time.
# ###########################################################################

parse_options "$T_LIB_DIR/samples/bash/po002.sh" --run-time 2 -- --defaults-file=/tmp/12345/my.sandbox.cnf

rm $TMPDIR/collect/*

collect "$TMPDIR/collect" "2011_12_05" > $p-output 2>&1

local iters=$(cat $p-df | grep -c '^TS ')
is "$iters" "2" "2 iteration/2s run time"

# ############################################################################
# Done
# ############################################################################
