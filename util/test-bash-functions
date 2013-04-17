#!/usr/bin/env bash

# This script is a test harness and TAP producer for testing bash functions
# in a bash file.  A bash and test file are sourced; the former provides the
# functions to test and the latter provides the testing.

# ############################################################################
# Standard startup, find the branch's root directory
# ############################################################################
LANG='en_US.UTF-8'

die() {
   echo $1 >&2
   exit 255
}

cwd="$PWD"
if [ -n "$PERCONA_TOOLKIT_BRANCH" ]; then
   BRANCH=$PERCONA_TOOLKIT_BRANCH
   cd $BRANCH
else
   while [ ! -f Makefile.PL ] && [ $(pwd) != "/" ]; do
      cd ..
   done
   if [ ! -f Makefile.PL ]; then
      die "Cannot find the root directory of the Percona Toolkit branch"
      exit 1
   fi
   BRANCH="$PWD"
fi
cd "$cwd"

BIN_DIR="$BRANCH/bin";
LIB_DIR="$BRANCH/lib/bash";
T_DIR="$BRANCH/t";
T_LIB_DIR="$BRANCH/t/lib";
SANDBOX_VERSION="$($BRANCH/sandbox/test-env version)"

# ############################################################################
# Paths
# ############################################################################

# Do not use PT_TMPDIR because the tools use it for their own secure tmpdir.
TEST_PT_TMPDIR="/tmp/percona-toolkit.test"
if [ ! -d $TEST_PT_TMPDIR ]; then
   mkdir $TEST_PT_TMPDIR
fi

# ############################################################################
# Subroutines
# ############################################################################

# Load (count) the tests and print a TAP-style test plan.
load_tests() {
   local test_files="$@"
   local i=0
   local n_tests=0
   for t in $test_files; do
      # Return unless the test file is bash.  There may be other types of
      # files in the tool's test dir.
      if [ ! -f $t ]; then
         continue
      fi
      head -n 1 $t | grep -q bash || continue

      tests[$i]=$t
      i=$((i + 1))

      number_of_tests=$(grep --max-count 1 '^TESTS=[0-9]' $t | cut -d'=' -f2)
      if [ -z "$number_of_tests" ]; then
         n_tests=$(( $n_tests + 1 ))
      else
         n_tests=$(( $n_tests + $number_of_tests ))
      fi
   done
   echo "1..$n_tests"
}

# Source a test file to run whatever it contains (hopefully tests!).
run_test() {
   local t=$1  # test file name, e.g. "group-by-all-01" for pt-diskstats
   rm -rf $TEST_PT_TMPDIR/* >/dev/null 2>&1

   # Tests assume that they're being ran from their own dir, so they access
   # sample files like "samples/foo.txt".  So cd to the dir of the test file
   # and run it.  But the test file may have been given as a relative path,
   # so run its basename after cd'ing to its directory.  Then cd back in case
   # other test files are in other dirs.
   cwd="$PWD"
   local t_dir=$(dirname $t)
   TEST_FILE=$(basename $t)
   cd $t_dir
   source ./$TEST_FILE
   cd $cwd

   return $?
}

# Print a TAP-style test result.
result() {
   local result=$1
   local test_name=${2:-""}
   testno=$((testno + 1))
   if [ $result -eq 0 ]; then
      echo "ok $testno - $TEST_FILE $test_name"
   else
      echo "not ok $testno - $TEST_FILE $test_name"
      failed_tests=$(( failed_tests + 1))
      echo "#   Failed '$test_command'" >&2
      if [ -f $TEST_PT_TMPDIR/failed_result ]; then
         cat $TEST_PT_TMPDIR/failed_result | sed -e 's/^/#   /' -e '30q' >&2
      fi
   fi
   return $result
}

plan() {
   local n_tests=${1:-""}
   if [ "$n_tests" ]; then
      echo "1..$n_tests"
   fi
}

done_testing() {
   echo "1..$testno"
}

#
# The following subs are for the test files to call.
#

pass() {
   local reason="${1:-""}"
   result 0 "$reason"
}

fail() {
   local reason="${1:-""}"
   result 1 "$reason"
}

skip() {
   local skip="$1"
   local number_of_tests="$2"
   local reason="${3:-""}"

   if [ $skip ]; then
      for n in $(seq $number_of_tests); do
         result 0 "# skip $n $reason"
      done
   fi
}

# TODO unperlify
like() {
   local got="$1"
   local regex="$2"
   local test_name=${3:-""}
   test_command="$got =~ m<$regex>"
   perl -e 'exit(scalar($ARGV[0] =~ m<^$ARGV[1]>msi ? 0 : 1))' "$got" "$regex"
   result $? "$test_name"
}

no_diff() {
   local got=$1
   local expected=$2
   local test_name=${3:-""}
   test_command="diff $got $expected"
   eval $test_command > $TEST_PT_TMPDIR/failed_result 2>&1
   result $? "$test_name"
}

is() {
   local got=$1
   local expected=$2
   local test_name=${3:-""}
   test_command="\"$got\" == \"$expected\""
   test "$got" = "$expected"
   result $? "$test_name"
}

file_is_empty() {
   local file=$1
   local test_name=${2:-""}
   test_command="-s $file"
   if [ ! -f "$file" ]; then
      echo "$file does not exist" > $TEST_PT_TMPDIR/failed_result
      result 1 "$test_name"
   fi
   if [ -s "$file" ]; then
      echo "$file is not empty:" > $TEST_PT_TMPDIR/failed_result
      cat "$file" >> $TEST_PT_TMPDIR/failed_result
      result 1 "$test_name"
   else
      result 0 "$test_name"
   fi
}

file_contains() {
   local file="$1"
   local pat="$2"
   local test_name=${3:-""}
   test_command="grep -q '$pat' '$file'"
   if [ ! -f "$file" ]; then
      echo "$file does not exist" > $TEST_PT_TMPDIR/failed_result
      result 1 "$test_name"
   fi
   grep -q "$pat" $file
   if [ $? -ne 0 ]; then
      echo "$file does not contain '$pat':" > $TEST_PT_TMPDIR/failed_result
      cat "$file" >> $TEST_PT_TMPDIR/failed_result
      result 1 "$test_name"
   else
      result 0 "$test_name"
   fi
}

cmd_ok() {
   local test_command=$1
   local test_name=${2:-""}
   eval $test_command
   result $? "$test_name"
}

dies_ok() {
   local test_command=$1
   local test_name=${2:-""}

   local result=1
   (
      eval $test_command
   ) 2>/dev/null &
   wait $!
   [ $? ] && result=0

   result $result "$test_name"
}

# Helper subs for slow boxes

wait_for_files() {
   for file in "$@"; do
      local slept=0
      while ! [ -f $file ]; do
         sleep 0.2;
         slept=$((slept + 1))
         [ $slept -ge 150 ] && break  # 30s
      done
   done
}

diag() {
   if [ $# -eq 1 -a -f "$1" ]; then
      echo "# $1:"
      awk '{print "# " $0}' "$1"
   else
      for line in "$@"; do
         echo "# $line"
      done
   fi
}

# ############################################################################
# Script starts here
# ############################################################################

testno=0
failed_tests=0

if [ $# -eq 0 ]; then
   TEST_FILE=$(basename "$0")
   TEST="${TEST_FILE%".t"}"
   source "$BRANCH/t/lib/bash/$TEST.sh"
else
   if [ $# -lt 2 ]; then
      die "Usage: test-bash-functions FILE TESTS"
   fi

   # Check and source the bash file.  This is the code being tested.
   # All its global vars and subs will be imported.
   bash_file=$1
   shift
   if [ ! -f "$bash_file" ]; then
      die "$bash_file does not exist"
   fi
   head -n1 $bash_file | grep -q -E 'bash|sh' || die "$bash_file is not a bash file"
   source $bash_file

   # Load (count) the tests so that we can write a TAP test plan like 1..5
   # for expecting 5 tests.  Perl prove needs this.
   declare -a tests
   load_tests "$@"

   # Run the test files.
   for t in "${tests[@]}"; do
      run_test $t
   done
fi

rm -rf $TEST_PT_TMPDIR
exit $failed_tests
