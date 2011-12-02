#!/usr/bin/env bash

TESTS=24

TMPFILE="$TEST_TMPDIR/parse-opts-output"

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/parse_options.sh"

# ############################################################################
# Parse options from POD using all default values.
# ############################################################################

TMPDIR="$TEST_TMPDIR"
parse_options "$T_LIB_DIR/samples/bash/po001.sh" "" 2>$TMPFILE

TEST_NAME="No warnings or errors"
is "`cat $TMPFILE`" ""

TEST_NAME="Default opts"
is "$OPT_STRING_OPT" ""
is "$OPT_STRING_OPT2" "foo"
is "$OPT_TYPELESS_OPTION" ""
is "$OPT_NOPTION" "yes"
is "$OPT_INT_OPT" ""
is "$OPT_INT_OPT2" "42"
is "$OPT_VERSION" ""

# ############################################################################
# Specify some opts, but use default values for the rest.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" --int-opt 50 --typeless-option --string-opt bar

TEST_NAME="User-specified opts with defaults"
is "$OPT_STRING_OPT" "bar" # specified
is "$OPT_STRING_OPT2" "foo"
is "$OPT_TYPELESS_OPTION" "yes" # specified
is "$OPT_NOPTION" "yes"
is "$OPT_INT_OPT" "50" # specified
is "$OPT_INT_OPT2" "42"
is "$OPT_VERSION" ""

# ############################################################################
# Negate an option like --no-option.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" --no-noption

TEST_NAME="Negated option"
is "$OPT_STRING_OPT" ""
is "$OPT_STRING_OPT2" "foo"
is "$OPT_TYPELESS_OPTION" ""
is "$OPT_NOPTION" "no" # negated
is "$OPT_INT_OPT" ""
is "$OPT_INT_OPT2" "42"
is "$OPT_VERSION" ""

# ############################################################################
# Short form.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" -v

TEST_NAME="Short form"
is "$OPT_VERSION" "yes"

# ############################################################################
# An unknown option should produce an error.
# ############################################################################

# Have to call this in a subshell because the error will cause an exit.
(
   parse_options "$T_LIB_DIR/samples/bash/po001.sh" --foo >$TMPFILE 2>&1
)
local err=$?
TEST_NAME="Non-zero exit on unknown option"
is "$err" "1"

TEST_NAME="Error on unknown option"
cmd_ok "grep -q 'Unknown option: foo' $TMPFILE"

# ############################################################################
# Done
# ############################################################################
exit
