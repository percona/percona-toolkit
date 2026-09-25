#!/usr/bin/env bash

plan 3

source "$LIB_DIR/alt_cmds.sh"

_seq 5 > $TEST_PT_TMPDIR/out
no_diff \
   $TEST_PT_TMPDIR/out \
   $T_LIB_DIR/samples/bash/seq1.txt \
   "_seq 5"

missing_cmd="pt-test-command-${BASHPID:-$$}"

while command -v "$missing_cmd" >/dev/null 2>&1; do
   missing_cmd="${missing_cmd}_x"
done

_which "$missing_cmd" > $TEST_PT_TMPDIR/out
file_is_empty \
   $TEST_PT_TMPDIR/out \
   "Empty line printed for non-existent command"

# Test _which with an existing command
# bash should exist on the system, because we are running this script with bash.
_which bash > $TEST_PT_TMPDIR/out
file_contains \
   $TEST_PT_TMPDIR/out \
   "bash" \
   "_which bash"
# ###########################################################################
# Done
# ###########################################################################
