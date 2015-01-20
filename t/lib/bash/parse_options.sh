#!/usr/bin/env bash

plan 84

TMPFILE="$TEST_PT_TMPDIR/parse-opts-output"
TOOL="pt-stalk"
PT_TMPDIR="$TEST_PT_TMPDIR"

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
# Negate an option like --nooption.
# https://bugs.launchpad.net/percona-toolkit/+bug/954990
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" --nonoption

is "$OPT_NOPTION" "" "--nooption negates option like --no-option"

# ############################################################################
# Short form.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" -v
is "$OPT_VERSION" "yes" "Short form"

# ############################################################################
# Command line options plus externals args.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po001.sh" --no-noption -- --foo

is "$OPT_NOPTION" "" "Negated option (--)"
is "$ARGV" "" "ARGV (--)"
is "$EXT_ARGV" "--foo" "External ARGV (--)"

# ############################################################################
# An unknown option should produce an error.
# ############################################################################

# Have to call this in a subshell because the error will cause an exit.
parse_options "$T_LIB_DIR/samples/bash/po001.sh" --foo >$TMPFILE 2>&1
cmd_ok "grep -q 'Unknown option: --foo' $TMPFILE" "Error on unknown option"

usage_or_errors "$T_LIB_DIR/samples/bash/po001.sh" >$TMPFILE 2>&1
err=$?
is "$err" "1" "Non-zero exit on unknown option"

# ###########################################################################
# --help
# ###########################################################################
parse_options "$T_LIB_DIR/samples/bash/po001.sh" --help
usage_or_errors "$T_LIB_DIR/samples/bash/po001.sh" >$TMPFILE 2>&1
cmd_ok \
   "grep -q \"For more information, 'man pt-stalk' or 'perldoc\" $TMPFILE" \
   "--help"

cmd_ok \
   "grep -q '  --string-opt2[ ]*String option with a default.' $TMPFILE" \
   "Command line options"

cmd_ok \
   "grep -q '\-\-string-opt[ ]*(No value)' $TMPFILE" \
   "Options and values after processing arguments"

# Don't interpolate.
parse_options "$T_LIB_DIR/samples/bash/po003.sh" --help
usage_or_errors "$T_LIB_DIR/samples/bash/po003.sh" >$TMPFILE 2>&1

cmd_ok \
   "grep -q 'Exit if the disk is less than this %full.' $TMPFILE" \
   "Don't interpolate --help descriptions"

# TRUE/FALSE for typeless options, like the Perl tools.
# https://bugs.launchpad.net/percona-toolkit/+bug/954990
parse_options "$BIN_DIR/pt-stalk" --help
usage_or_errors "$BIN_DIR/pt-stalk" >$TMPFILE 2>&1

cmd_ok \
   "grep -q '\-\-stalk[ ][ ]*TRUE' $TMPFILE" \
   "TRUE for specified option in --help"

cmd_ok \
   "grep -q '\-\-version[ ][ ]*FALSE' $TMPFILE" \
   "FALSE for non-specified option in --help"

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

# User-specified --config
parse_options "$T_LIB_DIR/samples/bash/po001.sh" --config "$T_LIB_DIR/samples/bash/config003.conf" --string-opt bar

is "$OPT_STRING_OPT" "bar" "--config string option"
is "$OPT_STRING_OPT2" "foo" "--config string option2"
is "$OPT_TYPELESS_OPTION" "" "--config typeless option"
is "$OPT_NOPTION" "yes" "--config negatable option"
is "$OPT_INT_OPT" "123" "--config int option"
is "$OPT_INT_OPT2" "42" "--config int option2"
is "$OPT_VERSION" "" "--config version option"
is "$ARGV" "" "--config ARGV"
is "$EXT_ARGV" "" "--config External ARGV"

# Multiple --config files, last should take precedence.
parse_options "$T_LIB_DIR/samples/bash/po001.sh" --config $T_LIB_DIR/samples/bash/config001.conf,$T_LIB_DIR/samples/bash/config002.conf

is "$OPT_STRING_OPT" "hello world" "Two --config string option"
is "$OPT_TYPELESS_OPTION" "yes" "Two --config typeless option"
is "$OPT_INT_OPT" "100" "Two --config int option"
is "$ARGV" "" "Two --config ARGV"
is "$EXT_ARGV" "--host=127.1 --user=daniel" "Two--config External ARGV"

# Spaces before and after the option[=value] lines.
parse_options "$T_LIB_DIR/samples/bash/po001.sh" --config $T_LIB_DIR/samples/bash/config004.conf

is "$OPT_STRING_OPT" "foo" "Default string option (spacey)"
is "$OPT_TYPELESS_OPTION" "yes" "Default typeless option (spacey)"
is "$OPT_INT_OPT" "123" "Default int option (spacey)"
is "$ARGV" "" "ARGV (spacey)"
is "$EXT_ARGV" "" "External ARGV (spacey)"

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
# Size options.
# ############################################################################

parse_options "$T_LIB_DIR/samples/bash/po004.sh" --disk-bytes-free 1T
is "$OPT_DISK_BYTES_FREE" "1099511627776" "Size: 1T"

parse_options "$T_LIB_DIR/samples/bash/po004.sh" --disk-bytes-free 1G
is "$OPT_DISK_BYTES_FREE" "1073741824" "Size: 1G"

parse_options "$T_LIB_DIR/samples/bash/po004.sh" --disk-bytes-free 1M
is "$OPT_DISK_BYTES_FREE" "1048576" "Size: 1M"

parse_options "$T_LIB_DIR/samples/bash/po004.sh" --disk-bytes-free 1K
is "$OPT_DISK_BYTES_FREE" "1024" "Size: 1K"

parse_options "$T_LIB_DIR/samples/bash/po004.sh" --disk-bytes-free 1k
is "$OPT_DISK_BYTES_FREE" "1024" "Size: 1k"

parse_options "$T_LIB_DIR/samples/bash/po004.sh" --disk-bytes-free 1
is "$OPT_DISK_BYTES_FREE" "1" "Size: 1"

parse_options "$T_LIB_DIR/samples/bash/po004.sh" --disk-bytes-free 100M
is "$OPT_DISK_BYTES_FREE" "104857600" "Size: 100M"

parse_options "$T_LIB_DIR/samples/bash/po004.sh"
is "$OPT_DISK_BYTES_FREE" "104857600" "Size: 100M default"

# ############################################################################
# Bug 1038995: pt-stalk notify-by-email fails
# https://bugs.launchpad.net/percona-toolkit/+bug/1038995
# ############################################################################

# This failed because --notify was misparsed as --no-tify
parse_options "$T_LIB_DIR/samples/bash/po005.sh"
is "$OPT_NOTIFY_BY_EMAIL" "" "Bug 1038995: --notify-by-email is empty by default"

parse_options "$T_LIB_DIR/samples/bash/po005.sh" --notify-by-email foo@bar.com
is "$OPT_NOTIFY_BY_EMAIL" "foo@bar.com" "Bug 1038995: ...but gets set without errors if specified"

# ############################################################################
# Bug 1266869: fails when $HOME unset
# https://bugs.launchpad.net/percona-toolkit/+bug/1266869
# ############################################################################

TMP_HOME="$HOME"
unset HOME 
OUTPUT=`parse_options $T_LIB_DIR/samples/bash/po001.sh 2>&1` 
echo "$OUTPUT" > "$TMPFILE"
cmd_ok "grep -q -v unbound $TMPFILE" "No error when \$HOME is not set"
HOME="$TMP_HOME"  # just in case further tests below need it


# ############################################################################
# Done
# ############################################################################
