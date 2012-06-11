#!/usr/bin/env bash

plan 10

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/tmpdir.sh"

is "$TMPDIR" "" "TMPDIR not defined"

mk_tmpdir
cmd_ok "test -d $TMPDIR" "mk_tmpdir makes secure tmpdir"

tmpdir=$TMPDIR;

rm_tmpdir
cmd_ok "test ! -d $tmpdir" "rm_tmpdir"

is "$TMPDIR" "" "rm_tmpdir resets TMPDIR"

# ###########################################################################
# User-specified tmpdir.
# ###########################################################################

dir="/tmp/use--tmpdir"

is "$TMPDIR" "" "TMPDIR not defined"

cmd_ok "test ! -d $dir" "--tmpdir does not exist yet"

mk_tmpdir $dir
is "$TMPDIR" "$dir" "mk_tmpdir uses --tmpdir"

cmd_ok "test -d $dir" "mk_tmpdir creates --tmpdir"

rm_tmpdir

cmd_ok "test ! -d $tmpdir" "rm_tmpdir removes --tmpdir"

# ###########################################################################
# Bug 945079: tmpdir should respect $TEMP
# ###########################################################################

tempdir_test () {
   new_TEMP="/tmp/tmpdir_test"
   rm -rf "$new_TEMP"
   mkdir "$new_TEMP"
   local TMPDIR="$new_TEMP/"

   mk_tmpdir

   is "$(dirname "$TMPDIR")" \
      "$new_TEMP"            \
      'mk_tmpdir respects $TMPDIR'

   rm_tmpdir

   rm -rf "$new_TEMP"
}

tempdir_test 

# ###########################################################################
# Done
# ###########################################################################
