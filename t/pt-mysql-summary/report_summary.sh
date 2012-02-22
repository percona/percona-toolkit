#!/bin/bash

TESTS=1
TMPDIR=$TEST_TMPDIR

TEST_NAME="report_summary"
OPT_SLEEP=1
OPT_DUMP_SCHEMAS="mysql"
NAME_VAL_LEN=25
_NO_FALSE_NEGATIVES=1
report_summary "samples/tempdir" "percona-toolkit" | tail -n+3 > $TMPDIR/got
no_diff "$TMPDIR/got" "samples/expected_result_report_summary.txt"
