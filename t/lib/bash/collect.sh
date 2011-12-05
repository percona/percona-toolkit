#!/usr/bin/env bash

TESTS=24

TMPFILE="$TEST_TMPDIR/parse-opts-output"
TMPDIR="$TEST_TMPDIR"
PATH="$PATH:$PERCONA_TOOLKIT_SANDBOX/bin"

mkdir "$TMPDIR/collect" 2>/dev/null

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/parse_options.sh"
source "$LIB_DIR/safeguards.sh"
source "$LIB_DIR/alt_cmds.sh"
source "$LIB_DIR/collect.sh"

parse_options "$T_LIB_DIR/samples/bash/po002.sh" -- --defaults-file=/tmp/12345/my.sandbox.cnf

collect "$TMPDIR/collect" "2011_12_05"

# ############################################################################
# Done
# ############################################################################
exit
