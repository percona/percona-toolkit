#!/usr/bin/env bash

TESTS=9

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/tmpdir.sh"

TEST_NAME="TMPDIR not defined"
is "$TMPDIR" ""

TEST_NAME="mk_tmpdir makes secure tmpdir"
mk_tmpdir
cmd_ok "test -d $TMPDIR"

tmpdir=$TMPDIR;

TEST_NAME="rm_tmpdir"
rm_tmpdir
cmd_ok "test ! -d $tmpdir"

TEST_NAME="rm_tmpdir resets TMPDIR"
is "$TMPDIR" "" 

# --tmpdir
OPT_TMPDIR="/tmp/use--tmpdir"

TEST_NAME="TMPDIR not defined"
is "$TMPDIR" ""

TEST_NAME="--tmpdir does not exist yet"
cmd_ok "test ! -d $OPT_TMPDIR"

mk_tmpdir
TEST_NAME="mk_tmpdir uses --tmpdir"
is "$TMPDIR" "/tmp/use--tmpdir"

TEST_NAME="mk_tmpdir creates --tmpdir"
cmd_ok "test -d $TMPDIR"

tmpdir=$TMPDIR;

TEST_NAME="rm_tmpdir removes --tmpdir"
rm_tmpdir
cmd_ok "test ! -d $tmpdir"
