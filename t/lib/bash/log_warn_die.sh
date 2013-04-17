#!/usr/bin/env bash

source "$LIB_DIR/log_warn_die.sh"

log "Hello world A!" > $TEST_PT_TMPDIR/log
cmd_ok \
   "grep -q 'Hello world A!' $TEST_PT_TMPDIR/log" \
   "log msg"

log "Hello" "world B!" > $TEST_PT_TMPDIR/log
cmd_ok \
   "grep -q 'Hello world B!' $TEST_PT_TMPDIR/log" \
   "log msg msg"

is \
   "$EXIT_STATUS" \
   "0" \
   "Exit status 0"

warn "Hello world C!" 2> $TEST_PT_TMPDIR/log
cmd_ok \
   "grep -q 'Hello world C!' $TEST_PT_TMPDIR/log" \
   "warn msg"

warn "Hello" "world D!" 2> $TEST_PT_TMPDIR/log
cmd_ok \
   "grep -q 'Hello world D!' $TEST_PT_TMPDIR/log" \
   "warn msg msg"

is \
   "$EXIT_STATUS" \
   "1" \
   "Exit status 1"

OPT_VERBOSE=1

info "Hello world 1!" > $TEST_PT_TMPDIR/log
file_is_empty \
   $TEST_PT_TMPDIR/log \
   "verbose=1 info"

log "Hello world 2!" > $TEST_PT_TMPDIR/log
file_is_empty \
   $TEST_PT_TMPDIR/log \
   "verbose=1 log"

warn "Hello world 3!" > $TEST_PT_TMPDIR/log 2>&1
file_contains \
   $TEST_PT_TMPDIR/log \
   "Hello world 3!" \
   "verbose=1 warn"

OPT_VERBOSE=2

info "Hello world 4!" > $TEST_PT_TMPDIR/log
file_is_empty \
   $TEST_PT_TMPDIR/log \
   "verbose=2 info"

log "Hello world 5!" > $TEST_PT_TMPDIR/log
file_contains \
   $TEST_PT_TMPDIR/log \
   "Hello world 5!" \
   "verbose=2 log"

warn "Hello world 6!" > $TEST_PT_TMPDIR/log 2>&1
file_contains \
   $TEST_PT_TMPDIR/log \
   "Hello world 6!" \
   "verbose=2 warn"

OPT_VERBOSE=3

info "Hello world 7!" > $TEST_PT_TMPDIR/log
file_contains \
   $TEST_PT_TMPDIR/log \
   "Hello world 7!" \
   "verbose=3 info"

log "Hello world 8!" > $TEST_PT_TMPDIR/log
file_contains \
   $TEST_PT_TMPDIR/log \
   "Hello world 8!" \
   "verbose=3 log"

warn "Hello world 9!" > $TEST_PT_TMPDIR/log 2>&1
file_contains \
   $TEST_PT_TMPDIR/log \
   "Hello world 9!" \
   "verbose=3 warn"

OPT_VERBOSE=0

info "Hello world 10!" > $TEST_PT_TMPDIR/log
file_is_empty \
   $TEST_PT_TMPDIR/log \
   "verbose=0 info"

log "Hello world 11!" > $TEST_PT_TMPDIR/log
file_is_empty \
   $TEST_PT_TMPDIR/log \
   "verbose=0 log"

warn "Hello world 12!" > $TEST_PT_TMPDIR/log 2>&1
file_is_empty \
   $TEST_PT_TMPDIR/log \
   "verbose=0 warn"

# ###########################################################################
# Done
# ###########################################################################
done_testing
