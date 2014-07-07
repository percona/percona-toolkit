#!/usr/bin/env bash

plan 12

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/safeguards.sh"

PT_TMPDIR="$TEST_PT_TMPDIR"
SAMPLE="$T_LIB_DIR/samples/bash"

disk_space "/" > $PT_TMPDIR/df-out
cmd_ok \
   "grep -q Avail $PT_TMPDIR/df-out" \
   "disk_space()"

is \
   "`wc -l $PT_TMPDIR/df-out | awk '{print $1}'`" \
   "2" \
   "2-line df output"

# Filesystem   1024-blocks     Used Available Capacity  Mounted on
# /dev/disk0s2   118153176 94409664  23487512    81%    /
#
# Those values are in Kb, so:
#   used     = 94409664 (94.4G) = 96_675_495_936 bytes
#   free     = 23487512 (23.4G) = 24_051_212_288 bytes
#   pct free = 100 - 81         = 19 %

# want free - 100, 18 < 19, so this should be ok.
check_disk_space "$SAMPLE/diskspace001.txt" 24051212188 18 >$PT_TMPDIR/out 2>&1
is "$?" "0" "Enough disk space"
is \
   "`cat $PT_TMPDIR/out`" \
   "" \
   "No output if enough disk space"

#  want free - 100 is ok, but 20 < 19 is not.
check_disk_space "$SAMPLE/diskspace001.txt" 24051212188 20 >$PT_TMPDIR/out 2>&1
is "$?" "1" "Not enough % free"

# want free + 100, so this should fail
# (real free is 100 bytes under what we want)
check_disk_space "$SAMPLE/diskspace001.txt" 24051212388 18 >$PT_TMPDIR/out 2>&1
is "$?" "1" "Not enough MB free"
cmd_ok \
   "grep -q 'Actual: 19% free, 24051212288 bytes free (- 0 bytes margin)' $PT_TMPDIR/out" \
   "Warning if not enough disk space"

# ###########################################################################
# Check with a margin (amount we plan to use in the future).
# ###########################################################################

# want free - 100 + 50 margin, so effectively want free - 50 is ok.
check_disk_space "$SAMPLE/diskspace001.txt" 24051212188 18 50
is "$?" "0" "Enough disk space with margin"

# want free - 100 + 101 margin, so real free is 1 byte under what we want.
check_disk_space "$SAMPLE/diskspace001.txt" 24051212188 18 101 >$PT_TMPDIR/out 2>&1
is "$?" "1" "Not enough MB free with margin"

# want free - 100 + 50 margin ok but %free will be 19 which is < 25.
check_disk_space "$SAMPLE/diskspace001.txt" 24051212188 25 50 >$PT_TMPDIR/out 2>&1
is "$?" "1" "Not enough % free with margin"
cmd_ok \
   "grep -q 'Actual:[ ]*19% free,' $PT_TMPDIR/out" \
   "Calculates % free with margin"

# #############################################################################
# NFS
# https://bugs.launchpad.net/percona-toolkit/+bug/1071979
# #############################################################################

check_disk_space "$SAMPLE/diskspace002.txt" 104857600 5 20971520
is "$?" "0" "df with NFS (bug 1071979)"

# ###########################################################################
# Done
# ###########################################################################
