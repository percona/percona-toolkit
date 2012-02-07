#!/bin/sh

port=$1
db=$2
tbl=$3
chunk=$4

/tmp/$port/use -e "select 1 from percona.checksums where db='$db' and tbl='$tbl' and chunk=$chunk" 2>/dev/null | grep -q 1 2>/dev/null
