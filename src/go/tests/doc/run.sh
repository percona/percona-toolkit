#!/bin/bash

set -e
set -x 

## Declare an array of images.
images=( \
    "mongo:3.6" \
    "mongo:4.0" \
    "mongo:4.2" \
    "mongo:4.4" \
    "percona/percona-server-mongodb:3.6" \
    "percona/percona-server-mongodb:4.0" \
    "percona/percona-server-mongodb:4.2" \
    "percona/percona-server-mongodb:4.4" \
)

## Run docker-compose from the location of the script.
cd $(dirname $0)

## Now loop through the above array of images.
for image in "${images[@]}"
do
    export MONGO_IMAGE=${image}
    # Clean up old instance if it got left running e.g. after ctrl+c.
    docker-compose down -v
    docker-compose up -d
    docker-compose exec mongo sh /script/main.sh
    docker-compose down -v
done
