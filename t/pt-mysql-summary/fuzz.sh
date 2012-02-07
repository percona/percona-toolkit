#!/bin/bash

TESTS=1
TMPDIR=$TEST_TMPDIR

TEST_NAME="fuzz 49"
is $(fuzz 49) "50"
