#!/usr/bin/env bash

TESTS=9

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/tmpdir.sh"

TEST_NAME="TMPDIR not defined"
is "$TMPDIR" ""

TEST_NAME="set_TMPDIR makes secure tmpdir"
set_TMPDIR
cmd_ok "test -d $TMPDIR"

tmpdir=$TMPDIR;

TEST_NAME="rm_TMPDIR"
rm_TMPDIR
cmd_ok "test ! -d $tmpdir"

TEST_NAME="rm_TMPDIR resets TMPDIR"
is "$TMPDIR" "" 

# --tmpdir
OPT_TMPDIR="/tmp/use--tmpdir"

TEST_NAME="TMPDIR not defined"
is "$TMPDIR" ""

TEST_NAME="--tmpdir does not exist yet"
cmd_ok "test ! -d $OPT_TMPDIR"

set_TMPDIR
TEST_NAME="set_TMPDIR uses --tmpdir"
is "$TMPDIR" "/tmp/use--tmpdir"

TEST_NAME="set_TMPDIR creates --tmpdir"
cmd_ok "test -d $TMPDIR"

tmpdir=$TMPDIR;

TEST_NAME="rm_TMPDIR removes --tmpdir"
rm_TMPDIR
cmd_ok "test ! -d $tmpdir"
