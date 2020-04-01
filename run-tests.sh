#!/bin/bash

BRANCH=$(git rev-parse --abbrev-ref HEAD)
MYSQL_VERSION=$(mysql -ss -e "SHOW VARIABLES LIKE 'version'" | cut  -f2)
LOG_FILE=~/${BRANCH}-${MYSQL_VERSION}.log

truncate --size=0 ${LOG_FILE}
echo "Logging to $LOG_FILE"

for dir in t/*
do 
    echo "$dir"
    sandbox/test-env restart
    prove -vw --trap --timer "$dir" | tee -a $LOG_FILE
done
