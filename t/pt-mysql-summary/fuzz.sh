#!/bin/bash

TESTS=1

TEST_NAME="fuzz 49"
is $(fuzz 49) "50"
