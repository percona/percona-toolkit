#!/usr/bin/env bash

TESTS=7

TMPDIR="$TEST_TMPDIR"
local file="$TMPDIR/pid-file"

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/daemon.sh"

cmd_ok \
   "test ! -f $file" \
   "PID file doesn't exist"

make_pid_file $file $$

cmd_ok \
   "test -f $file" \
   "PID file created"

local pid=`cat $file`
is \
   "$pid" \
   "$$" \
   "Correct PID"

remove_pid_file $file

cmd_ok \
   "test ! -f $file" \
   "PID file removed"

# ###########################################################################
# PID file already exists and proc is running.
# ###########################################################################
echo $$ > $file

(
   make_pid_file $file $$ >$TMPDIR/output 2>&1
)

cmd_ok \
   "grep -q \"PID file /tmp/percona-toolkit.test/pid-file already exists and its PID ($$) is running\" $TMPDIR/output" \
   "Does not overwrite PID file is PID is running"

echo 999999 > $file

make_pid_file $file $$ >$TMPDIR/output 2>&1

cmd_ok \
   "grep -q 'Overwriting PID file /tmp/percona-toolkit.test/pid-file because its PID (999999) is not running' $TMPDIR/output" \
   "Overwrites PID file if PID is not running"

pid=`cat $file`
is \
   "$pid" \
   "$$" \
   "Correct PID"

rm $file
rm $TMPDIR/output

# ###########################################################################
# Done.
# ###########################################################################
