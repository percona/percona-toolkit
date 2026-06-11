#!/bin/bash

MYSQL_VERSION=$(mysql -ss -e "SELECT VERSION()")
LOGFILE=${HOME}/pt-tests-$(git rev-parse --abbrev-ref HEAD)-mysql-${MYSQL_VERSION}.log
echo "" > ${LOGFILE}

export PERCONA_TOOLKIT_SANDBOX=${HOME}/mysql/my-5.7
for d in $(ls -d t/*)
do
    sandbox/test-env restart
    prove -vw $d | tee -a ${LOGFILE}
done

