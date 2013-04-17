#!/usr/bin/env bash

plan 9

PT_TMPDIR="$TEST_PT_TMPDIR"
file="$PT_TMPDIR/pid-file"

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/daemon.sh"

cmd_ok \
   "test ! -f $file" \
   "PID file doesn't exist"

make_pid_file $file $$

cmd_ok \
   "test -f $file" \
   "PID file created"

pid=`cat $file`
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
   make_pid_file $file $$ >$PT_TMPDIR/output 2>&1
)

cmd_ok \
   "grep -q \"PID file /tmp/percona-toolkit.test/pid-file already exists and its PID ($$) is running\" $PT_TMPDIR/output" \
   "Does not overwrite PID file is PID is running"

echo 999999 > $file

make_pid_file $file $$ >$PT_TMPDIR/output 2>&1

cmd_ok \
   "grep -q 'Overwriting PID file /tmp/percona-toolkit.test/pid-file because its PID (999999) is not running' $PT_TMPDIR/output" \
   "Overwrites PID file if PID is not running"

pid=`cat $file`
is \
   "$pid" \
   "$$" \
   "Correct PID"

rm $file
rm $PT_TMPDIR/output

# ###########################################################################
# Die if pid file can't be created.
# ###########################################################################
(
   make_pid_file "/root/pid" $$ >$PT_TMPDIR/output 2>&1
)

is \
   "$?" \
   "1" \
   "Exit 1 if PID file can't be created"

cmd_ok \
   "grep -q 'Cannot create or write PID file /root/pid' $PT_TMPDIR/output" \
   "Error that PID file can't be created"

# ###########################################################################
# Done.
# ###########################################################################
