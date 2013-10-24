#!/bin/sh

SOURCE="${BASH_SOURCE[0]}"

echo $(SOURCE)

CONFIG=${dirname(SOURCE)}/etc/fyler.config

echo ${CONFIG}

if [ -f $CONFIG ]
then

mytemp=`grep storage_dir $fil | tail -1 | cut -d = -f2 | cut -d : -f1`
echo "Current temperature is: $mytemp"

fi

#find ${DIR} -mtime +1 -exec rm {} \;