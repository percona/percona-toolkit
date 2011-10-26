#!/usr/bin/env bash

TESTS=17

source "$LIB_DIR/parse_options.sh"

parse_options "$T_LIB_DIR/samples/bash/po001.sh"

is "$THRESHOLD" "100"
is "$VARIABLE" "Threads_connected"
is "$CYCLES" "1"
is "$GDB" "no"
is "$OPROFILE" "yes"
is "$STRACE" "no"
is "$TCPDUMP" "yes"
is "$EMAIL" ""
is "$INTERVAL" "30"
is "$MAYBE_EMPTY" "no"
is "$COLLECT" "${HOME}/bin/pt-collect"
is "$DEST" "${HOME}/collected/"
is "$DURATION" "30"
is "$SLEEP" "300"
is "$PCT_THRESHOLD" "95"
is "$MB_THRESHOLD" "100"
is "$PURGE" "30"
