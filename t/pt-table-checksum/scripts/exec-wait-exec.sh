#!/bin/sh

port=$1
query1=$2
t=$3
query2=$4

/tmp/$port/use -e "$query1"
sleep $t
/tmp/$port/use -e "$query2"
