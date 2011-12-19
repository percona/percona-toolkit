#!/usr/bin/env bash

TESTS=11

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/safeguards.sh"

TMPDIR="$TEST_TMPDIR"
SAMPLE="$T_LIB_DIR/samples/bash"

disk_space "/" > $TMPDIR/df-out
cmd_ok \
   "grep -q Avail $TMPDIR/df-out" \
   "disk_space()"

is \
   "`wc -l $TMPDIR/df-out | awk '{print $1}'`" \
   "2" \
   "2-line df output"

check_disk_space "$SAMPLE/diskspace001.txt" 22000 18 >$TMPDIR/out 2>&1
is "$?" "0" "Enough disk space"
is \
   "`cat $TMPDIR/out`" \
   "" \
   "No output if enough disk space"

check_disk_space "$SAMPLE/diskspace001.txt" 24000 18 >$TMPDIR/out 2>&1
is "$?" "1" "Not enough MB free"
cmd_ok \
   "grep -q '19% free, 23487512 KB free; wanted more than 18% free or 24576000 KB free' $TMPDIR/out" \
   "Warning if not enough disk space"

check_disk_space "$SAMPLE/diskspace001.txt" 22000 19 >$TMPDIR/out 2>&1
is "$?" "1" "Not enough % free"

# ###########################################################################
# Check with a margin (amount we plan to use in the future).
# ###########################################################################

check_disk_space "$SAMPLE/diskspace001.txt" 22000 18 100
is "$?" "0" "Enough disk space with margin"

check_disk_space "$SAMPLE/diskspace001.txt" 23000 18 100 >$TMPDIR/out 2>&1
is "$?" "1" "Not enough MB free with margin"

check_disk_space "$SAMPLE/diskspace001.txt" 100 5 20000 >$TMPDIR/out 2>&1
is "$?" "1" "Not enough % free with margin"
cmd_ok \
   "grep -q '3% free,' $TMPDIR/out" \
   "Calculates % free with margin"

# ###########################################################################
# Done
# ###########################################################################
