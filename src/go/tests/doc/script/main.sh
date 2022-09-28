#!/bin/sh

set -e
set -x

DIR=$(dirname "$0")

# import funcs
for f in $(ls $DIR/func)
do
. "${DIR}/func/${f}"
done

# wait until mongo is available
until mongo --eval 'db.serverStatus()' > /dev/null
do
    sleep 1
done

# declare list of profile funcs to run
profiles=$(ls $DIR/profile)

MONGO_VERSION="$(db_version)"
RESULT_DIR=${RESULT_DIR:-/out}

# turn on profiling
set_profiling_level

for p in $profiles
do
    f="${p%.*}"
    cat "${DIR}/profile/${p}" | mongo
    get_single_profile > "${RESULT_DIR}/${f}_${MONGO_VERSION}"
done
