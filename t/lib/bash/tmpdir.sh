#!/usr/bin/env bash

TESTS=9

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/tmpdir.sh"

is "$TMPDIR" "" "TMPDIR not defined"

mk_tmpdir
cmd_ok "test -d $TMPDIR" "mk_tmpdir makes secure tmpdir"

tmpdir=$TMPDIR;

rm_tmpdir
cmd_ok "test ! -d $tmpdir" "rm_tmpdir"

is "$TMPDIR" "" "rm_tmpdir resets TMPDIR"

# --tmpdir
OPT_TMPDIR="/tmp/use--tmpdir"

is "$TMPDIR" "" "TMPDIR not defined"

cmd_ok "test ! -d $OPT_TMPDIR" "--tmpdir does not exist yet"

mk_tmpdir
is "$TMPDIR" "/tmp/use--tmpdir" "mk_tmpdir uses --tmpdir"

cmd_ok "test -d $TMPDIR" "mk_tmpdir creates --tmpdir"

tmpdir=$TMPDIR;

rm_tmpdir
cmd_ok "test ! -d $tmpdir" "rm_tmpdir removes --tmpdir"
