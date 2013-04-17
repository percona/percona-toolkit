#!/usr/bin/env bash

plan 1

source "$LIB_DIR/alt_cmds.sh"

_seq 5 > $TEST_PT_TMPDIR/out
no_diff \
   $TEST_PT_TMPDIR/out \
   $T_LIB_DIR/samples/bash/seq1.txt \
   "_seq 5"

# ###########################################################################
# Done
# ###########################################################################
