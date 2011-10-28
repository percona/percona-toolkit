#!/usr/bin/env bash

TESTS=37

TMPFILE="$TEST_TMPDIR/parse-opts-output"

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/parse_options.sh"

# ############################################################################
# Parse options from POD using all default values.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" "" 2>$TMPFILE

TEST_NAME="No warnings or errors"
is "`cat $TMPFILE`" ""

TEST_NAME="Default opts"
is "$OPT_THRESHOLD" "100"
is "$OPT_VARIABLE" "Threads_connected"
is "$OPT_CYCLES" "1"
is "$OPT_GDB" "no"
is "$OPT_OPROFILE" "yes"
is "$OPT_STRACE" "no"
is "$OPT_TCPDUMP" "yes"
is "$OPT_EMAIL" ""
is "$OPT_INTERVAL" "30"
is "$OPT_MAYBE_EMPTY" "no"
is "$OPT_COLLECT" "${HOME}/bin/pt-collect"
is "$OPT_DEST" "${HOME}/collected/"
is "$OPT_DURATION" "30"
is "$OPT_SLEEP" "300"
is "$OPT_PCT_THRESHOLD" "95"
is "$OPT_MB_THRESHOLD" "100"
is "$OPT_PURGE" "30"

# ############################################################################
# Specify some opts, but use default values for the rest.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" --threshold 50 --gdb yes --email user@example.com

TEST_NAME="User-specified opts with defaults"
is "$OPT_THRESHOLD" "50" # specified
is "$OPT_VARIABLE" "Threads_connected"
is "$OPT_CYCLES" "1"
is "$OPT_GDB" "yes" # specified
is "$OPT_OPROFILE" "yes"
is "$OPT_STRACE" "no"
is "$OPT_TCPDUMP" "yes"
is "$OPT_EMAIL" "user@example.com" # specified
is "$OPT_INTERVAL" "30"
is "$OPT_MAYBE_EMPTY" "no"
is "$OPT_COLLECT" "${HOME}/bin/pt-collect"
is "$OPT_DEST" "${HOME}/collected/"
is "$OPT_DURATION" "30"
is "$OPT_SLEEP" "300"
is "$OPT_PCT_THRESHOLD" "95"
is "$OPT_MB_THRESHOLD" "100"
is "$OPT_PURGE" "30"

# ############################################################################
# An unknown option should produce an error.
# ############################################################################

# Have to call this in a subshell because the error will cause an exit.
(
   parse_options "$T_LIB_DIR/samples/bash/po001.sh" --foo >$TMPFILE 2>&1
)
local err=$?
TEST_NAME="Non-zero exit on unknown option"
is "$err" "1"

TEST_NAME="Error on unknown option"
cmd_ok "grep -q 'Unknown option: foo' $TMPFILE"

# ############################################################################
# Done
# ############################################################################
exit
