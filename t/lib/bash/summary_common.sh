#!/usr/bin/env bash

plan 3

TMPDIR="$TEST_TMPDIR"
PATH="$PATH:$PERCONA_TOOLKIT_SANDBOX/bin"

. "$LIB_DIR/summary_common.sh"

p="$TMPDIR/get_var_samples"

echo "test1    abcdef" > "$p"
is \
   "$(get_var test1 "$p")" \
   "abcdef"                \
   "Sanity check, get_var works"

echo "test2    abc def" > "$p"
is \
   "$(get_var test2 "$p")" \
   "abc def"                \
   "get_var works even if the value has spaces"

echo "test::1    abcdef" > "$p"
is \
   "$(get_var "test::1" "$p")" \
   "abcdef"                \
   "get_var works if the 'key' has colons"

