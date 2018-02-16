#!/bin/sh

set -e
set -x 

## Declare an array of images.
declare -a images=(
    "mongo:2.6.12"
    "mongo:3.0.15"
    "mongo:3.2.19"
    "mongo:3.4.12"
    "mongo:3.6.2"
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
