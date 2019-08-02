#!/bin/bash

tries=1
max_tries=60
sleep_secs=1

while [ $tries -lt $max_tries ]; do
	docker-compose ps init 2>/dev/null | grep -q 'Exit 0'
	[ $? == 0 ] && break
	echo "# INFO: 'init' has not completed, retrying check in $sleep_secs secs (try $tries/$max_tries)"
	sleep $sleep_secs
	tries=$(($tries + 1))
done
if [ $tries -ge $max_tries ]; then
        echo "# ERROR: reached max tries $max_tries, exiting"
        exit 1
fi
