#!/usr/bin/env bash

plan 3

TMPFILE="$TEST_PT_TMPDIR/parse-opts-output"
TOOL="pt-mysql-summary"
PT_TMPDIR="$TEST_PT_TMPDIR"

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/parse_options.sh"
source "$LIB_DIR/mysql_options.sh"

cnf="/tmp/12345/my.sandbox.cnf"

parse_options "$PERCONA_TOOLKIT_BRANCH/bin/pt-mysql-summary" --defaults-file $cnf
is "$OPT_DEFAULTS_FILE" "$cnf" "--defaults-file works"

# ############################################################################
# --host's default works
# ############################################################################

parse_options "$PERCONA_TOOLKIT_BRANCH/bin/pt-mysql-summary"
is "$OPT_HOST" "localhost" "--host has default: localhost"

# ############################################################################
# Short forms work
# ############################################################################

parse_options "$PERCONA_TOOLKIT_BRANCH/bin/pt-mysql-summary" -F $cnf
is "$OPT_DEFAULTS_FILE" "$cnf" "-F works"

# ############################################################################
# Done
# ############################################################################
