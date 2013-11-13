#!/bin/bash

echo [$(date +"%Y-%m-%d %H:%M:%S")] Flush temporary files begins.

SOURCE="${BASH_SOURCE[0]}"

ROOT_DIR=$( dirname "${SOURCE}")

CONFIG=${ROOT_DIR}/etc/fyler.config

DIR=FALSE

if [ -f $CONFIG ]
then

while read line
  do
    echo $line | grep -q storage_dir
    if [ $? == 0 ]; then
        re="^\{storage_dir,\"([^\}]+)\"\}\.$"
        [[ $line =~ $re ]] && var1="${BASH_REMATCH[1]}" && DIR=${var1}/
    fi
  done < $CONFIG

else

echo 'not_a_file'

exit 0

fi

find ${DIR} -mindepth 1 -maxdepth 1 -type d -mtime +1 -exec rm -R {} \;

echo [$(date +"%Y-%m-%d %H:%M:%S")] Flush complete.

exit 1