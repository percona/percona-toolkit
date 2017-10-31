#!/bin/sh

set -e
set -x 

## declare an array of images
declare -a images=(
    "mongo:2.6"
    "mongo:3.0"
    "mongo:3.2"
    "mongo:3.4"
    "mongo:3.5"
)

## now loop through the above array of images
for image in "${images[@]}"
do
    export MONGO_IMAGE=$image
    # clean up old instance if it got left running e.g. after ctrl+c
    docker-compose down -v
    docker-compose up -d
    docker-compose exec mongo sh /script/main.sh
    docker-compose down -v
done
