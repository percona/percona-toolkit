#!/usr/bin/env bash

plan 10

PT_TMPDIR="$TEST_PT_TMPDIR"
PATH="$PATH:$PERCONA_TOOLKIT_SANDBOX/bin"

. "$LIB_DIR/summary_common.sh"

p="$PT_TMPDIR/get_var_samples"

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


echo "1234/567    qwerty" > "$p"
is \
   "$(get_var "1234/567" "$p")" \
   "qwerty"                \
   "get_var works if the 'key' has a dash in it"


echo ".*    some_new_value" >> "$p"
is \
   "$(get_var ".*" "$p")" \
   "some_new_value"                \
   "get_var treats the variable as a literal, not a regex"

if get_var "definitely_does_not_exist" "$p" 1>/dev/null ; then
   pass "get_var always returns true, even for variables that don't exist"
else
   fail "get_var should always return true"
fi

samples="$PERCONA_TOOLKIT_BRANCH/t/pt-mysql-summary/samples"

is \
   "$(get_var "table_open_cache" "$samples/temp002/mysql-variables")" \
   "400"                \
   "get_var works on a variables dump"

is \
   "$(get_var "Open_tables" "$samples/temp002/mysql-status")" \
   "40"                \
   "get_var works on a status dump"

cat <<EOF > "$p"
internal::nice_of_2750    0
internal::nice_of_2571    0
internal::nice_of_2406    0

EOF

is \
   "$(get_var "internal::nice_of_2750" "$p")" \
   "0"                \
   "get_var doesn't get confused if \$2 is also found inside \$1"

# setup_data_dir

dies_ok \
   "setup_data_dir $PERCONA_TOOLKIT_BRANCH" \
   "setup_data_dir dies if passed a populated directory" 2>/dev/null

