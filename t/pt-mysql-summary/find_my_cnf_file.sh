#!/usr/bin/env bash

TESTS=4
TMPDIR=$TEST_TMPDIR

TEST_NAME="ps-mysqld-001.txt"
res=$(find_my_cnf_file samples/ps-mysqld-001.txt)
is "$res" "/tmp/12345/my.sandbox.cnf"

TEST_NAME="ps-mysqld-001.txt with port"
res=$(find_my_cnf_file samples/ps-mysqld-001.txt 12346)
is "$res" "/tmp/12346/my.sandbox.cnf"

TEST_NAME="ps-mysqld-004.txt"
res=$(find_my_cnf_file samples/ps-mysqld-004.txt)
is "$res" "/var/lib/mysql/my.cnf"

TEST_NAME="ps-mysqld-004.txt with port"
res=$(find_my_cnf_file samples/ps-mysqld-004.txt 12345)
is "$res" "/var/lib/mysql/my.cnf"
