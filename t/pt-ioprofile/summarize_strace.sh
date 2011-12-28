#!/usr/bin/env bash

TESTS=2

source "$BIN_DIR/pt-ioprofile"

SAMPLES="$T_DIR/samples"

# ###########################################################################
# summarize_strace sum times filename
# ###########################################################################

summarize_strace          \
   "sum"                  \
   "times"                \
   "filename"             \
   "$SAMPLES/001-tab.txt" \
> $TEST_TMPDIR/got

no_diff \
   $TEST_TMPDIR/got \
   $SAMPLES/001-summarized-sum-times-filename.txt \
   "summarize_strace sum times filename"

# ###########################################################################
# Group by all.
# ###########################################################################

summarize_strace          \
   "sum"                  \
   "times"                \
   "all"                  \
   "$SAMPLES/002-tab.txt" \
> $TEST_TMPDIR/got

no_diff \
   $TEST_TMPDIR/got \
   $SAMPLES/002-summarized-sum-times-all.txt \
   "summarize_strace sum times all"

# ###########################################################################
# Done.
# ###########################################################################
