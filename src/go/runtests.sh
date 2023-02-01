#!/bin/bash
set -e
export BASEDIR=$(git rev-parse --show-toplevel)
export CHECK_SESSIONS=0
cd $BASEDIR

source ${BASEDIR}/src/go/setenv.sh

for dir in $(ls -d ./src/go/pt-* ) ./src/go/mongolib
do 
  echo "Running tests at $BASEDIR/$dir"
  cd $BASEDIR/$dir
  go get ./...
  go test -v -coverprofile=coverage.out ./...
  if [ -f coverage.out ]
  then
      go tool cover -func=coverage.out
      rm coverage.out
  fi
done
