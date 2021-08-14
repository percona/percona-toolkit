#!/bin/bash

DIR=$(dirname "$0")
source ${DIR}/env.sh

# import funcs
for f in $(ls $DIR/func)
do
. "${DIR}/func/${f}"
done

MONGO_VERSION="$(db_version)"
VENDOR_NAME="$(vendor_name)"
RESULT_DIR=${RESULT_DIR:-/out}

# wait until mongo is available
until $CMD --eval 'db.serverStatus()' > /dev/null
do
    sleep 1
done

# turn on profiling
set_profiling_level

for p in $(ls ${DIR}/queries); do 
    f="${p%.*}"
    cat "${DIR}/js/reset_profiler.js" | $CMD
    cat "${DIR}/queries/$p" | $CMD
    get_single_profile > "${RESULT_DIR}/${f}_${VENDOR_NAME}_${MONGO_VERSION}"
done