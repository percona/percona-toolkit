#!/usr/bin/env bash

plan 10

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/tmpdir.sh"

is "$PT_TMPDIR" "" "PT_TMPDIR not defined"

mk_tmpdir
cmd_ok "test -d $PT_TMPDIR" "mk_tmpdir makes secure tmpdir"

tmpdir="$PT_TMPDIR";

rm_tmpdir
cmd_ok "test ! -d $tmpdir" "rm_tmpdir"

is "$PT_TMPDIR" "" "rm_tmpdir resets PT_TMPDIR"

# ###########################################################################
# User-specified tmpdir.
# ###########################################################################

dir="/tmp/use--tmpdir"

is "$PT_TMPDIR" "" "PT_TMPDIR not defined"

cmd_ok "test ! -d $dir" "--tmpdir does not exist yet"

mk_tmpdir $dir
is "$PT_TMPDIR" "$dir" "mk_tmpdir uses --tmpdir"

cmd_ok "test -d $dir" "mk_tmpdir creates --tmpdir"

rm_tmpdir

cmd_ok "test ! -d $tmpdir" "rm_tmpdir removes --tmpdir"

# ###########################################################################
# Bug 945079: tmpdir should respect $TEMP
# ###########################################################################

tempdir_test () {
   local new_TEMP="/tmp/tmpdir_test"
   [ -d "$new_TEMP" ] || mkdir "$new_TEMP"
   export TMPDIR="$new_TEMP"

   mk_tmpdir

   is "$(dirname "$PT_TMPDIR")" \
      "$new_TEMP"            \
      'mk_tmpdir respects $PT_TMPDIR'

   rm_tmpdir

   rm -rf "$new_TEMP"
}

tempdir_test 

# ###########################################################################
# Done
# ###########################################################################
