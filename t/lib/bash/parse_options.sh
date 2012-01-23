#!/usr/bin/env bash

TESTS=46

TMPFILE="$TEST_TMPDIR/parse-opts-output"
TOOL="pt-stalk"
TMPDIR="$TEST_TMPDIR"

source "$LIB_DIR/log_warn_die.sh"
source "$LIB_DIR/parse_options.sh"

# ############################################################################
# Parse options from POD using all default values.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" 2>$TMPFILE

is "`cat $TMPFILE`" "" "No warnings or errors"

is "$OPT_STRING_OPT" "" "Default string option"
is "$OPT_STRING_OPT2" "foo" "Default string option with default"
is "$OPT_TYPELESS_OPTION" "" "Default typeless option"
is "$OPT_NOPTION" "yes" "Default neg option"
is "$OPT_INT_OPT" "" "Default int option"
is "$OPT_INT_OPT2" "42" "Default int option with default"
is "$OPT_VERSION" "" "--version"

# ############################################################################
# Specify some opts, but use default values for the rest.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" --int-opt 50 --typeless-option --string-opt bar

is "$OPT_STRING_OPT" "bar" "Specified string option (spec)"
is "$OPT_STRING_OPT2" "foo" "Default string option with default (spec)"
is "$OPT_TYPELESS_OPTION" "yes" "Specified typeless option (spec)"
is "$OPT_NOPTION" "yes" "Default neg option (spec)"
is "$OPT_INT_OPT" "50" "Specified int option (spec)"
is "$OPT_INT_OPT2" "42" "Default int option with default (spec)"
is "$OPT_VERSION" "" "--version (spec)"
is "$ARGV" "" "ARGV"
is "$EXT_ARGV" "" "External ARGV"

# ############################################################################
# --option=value should work like --option value.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" --int-opt=42

is "$OPT_INT_OPT" "42" "Specified int option (--option=value)"

parse_options "$T_LIB_DIR/samples/bash/po001.sh" --string-opt="hello world"

is "$OPT_STRING_OPT" "hello world" "Specified int option (--option=\"value\")"

# ############################################################################
# Negate an option like --no-option.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" --no-noption

is "$OPT_STRING_OPT" "" "Default string option (neg)"
is "$OPT_STRING_OPT2" "foo" "Default string option with default (neg)"
is "$OPT_TYPELESS_OPTION" "" "Default typeless option (neg)"
is "$OPT_NOPTION" "" "Negated option (neg)"
is "$OPT_INT_OPT" "" "Default int option (neg)"
is "$OPT_INT_OPT2" "42" "Default int option with default (neg)"
is "$OPT_VERSION" "" "--version (neg)"

# ############################################################################
# Short form.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" -v
is "$OPT_VERSION" "yes" "Short form"

# ############################################################################
# An unknown option should produce an error.
# ############################################################################

# Have to call this in a subshell because the error will cause an exit.
parse_options "$T_LIB_DIR/samples/bash/po001.sh" --foo >$TMPFILE 2>&1
cmd_ok "grep -q 'Unknown option: --foo' $TMPFILE" "Error on unknown option"

usage_or_errors "$T_LIB_DIR/samples/bash/po001.sh" >$TMPFILE 2>&1
local err=$?
is "$err" "1" "Non-zero exit on unknown option"

# ###########################################################################
# --help
# ###########################################################################
parse_options "$T_LIB_DIR/samples/bash/po001.sh" --help
usage_or_errors "$T_LIB_DIR/samples/bash/po001.sh" >$TMPFILE 2>&1
cmd_ok \
   "grep -q \"For more information, 'man pt-stalk' or 'perldoc\" $TMPFILE" \
   "--help"

# Don't interpolate.
parse_options "$T_LIB_DIR/samples/bash/po003.sh" --help
usage_or_errors "$T_LIB_DIR/samples/bash/po003.sh" >$TMPFILE 2>&1

cmd_ok \
   "grep -q 'Exit if the disk is less than this %full.' $TMPFILE" \
   "Don't interpolate --help descriptions"

# ###########################################################################
# Config files.
# ###########################################################################
TOOL="pt-test"
cp "$T_LIB_DIR/samples/bash/config001.conf" "$HOME/.$TOOL.conf"

parse_options "$T_LIB_DIR/samples/bash/po001.sh"

is "$OPT_STRING_OPT" "abc" "Default string option (conf)"
is "$OPT_STRING_OPT2" "foo" "Default string option with default (conf)"
is "$OPT_TYPELESS_OPTION" "yes" "Default typeless option (conf)"
is "$OPT_NOPTION" "yes" "Default neg option (conf)"
is "$OPT_INT_OPT" "" "Default int option (conf)"
is "$OPT_INT_OPT2" "42" "Default int option with default (conf)"
is "$OPT_VERSION" "" "--version (conf)"
is "$ARGV" "" "ARGV (conf)"
is "$EXT_ARGV" "--host=127.1 --user=daniel" "External ARGV (conf)"

# Command line should override config file.
parse_options "$T_LIB_DIR/samples/bash/po001.sh" --string-opt zzz

is "$OPT_STRING_OPT" "zzz" "Command line overrides config file"

# ############################################################################
# Option values with spaces.
# ############################################################################

# Config file
cp "$T_LIB_DIR/samples/bash/config002.conf" "$HOME/.$TOOL.conf"

parse_options "$T_LIB_DIR/samples/bash/po001.sh" ""

is "$OPT_STRING_OPT" "hello world" "Option value with space (conf)"
is "$OPT_INT_OPT" "100" "Option = value # comment (conf)"

rm "$HOME/.$TOOL.conf"
TOOL="pt-stalk"

# Command line
parse_options "$T_LIB_DIR/samples/bash/po001.sh" --string-opt "hello world"
is "$OPT_STRING_OPT" "hello world" "Option value with space (cmd line)"
is "$ARGV" "" "ARGV (cmd line)"
is "$EXT_ARGV" "" "External ARGV (cmd line)"

# ############################################################################
# Done
# ############################################################################
