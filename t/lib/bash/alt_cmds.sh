#!/usr/bin/env bash

TESTS=1

source "$LIB_DIR/alt_cmds.sh"

_seq 5 > $TEST_TMPDIR/out
no_diff \
   $TEST_TMPDIR/out \
   $T_LIB_DIR/samples/bash/seq1.txt \
   "_seq 5"

# ###########################################################################
# Done
# ###########################################################################
