#!/usr/bin/env bash

TESTS=6

source "$LIB_DIR/log_warn_die.sh"

log "Hello world!" > $TEST_TMPDIR/log
cmd_ok \
   "grep -q 'Hello world!' $TEST_TMPDIR/log" \
   "log msg"

log "Hello" "world!" > $TEST_TMPDIR/log
cmd_ok \
   "grep -q 'Hello world!' $TEST_TMPDIR/log" \
   "log msg msg"

is \
   "$EXIT_STATUS" \
   "0" \
   "Exit status 0"

warn "Hello world!" 2> $TEST_TMPDIR/log
cmd_ok \
   "grep -q 'Hello world!' $TEST_TMPDIR/log" \
   "warn msg"

warn "Hello" "world!" 2> $TEST_TMPDIR/log
cmd_ok \
   "grep -q 'Hello world!' $TEST_TMPDIR/log" \
   "warn msg msg"

is \
   "$EXIT_STATUS" \
   "1" \
   "Exit status 1"

# ###########################################################################
# Done
# ###########################################################################
