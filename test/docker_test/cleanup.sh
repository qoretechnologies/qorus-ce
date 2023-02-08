#!/bin/bash

set +e
set +x

. /tmp/env.sh

if [ -z "${OMQ_DIR}" ]; then
    echo "\$OMQ_DIR not defined. Exiting."
    exit 0
fi

# drop the schema
if [ -f "${OMQ_DIR}/etc/options" ]; then
    echo "qorus-client.allow-drop-schema: true" >> $OMQ_DIR/etc/options
    schema-tool --drop-schema -f
else
    echo "\${OMQ_DIR}/etc/options file does not exist. Skipping schema drop."
fi

OMQ_DIR_NAME=`basename ${OMQ_DIR}`
get_qorus_process_pid() {
    ps ax | grep "${OMQ_DIR_NAME}/bin/q" | grep -v "grep" | xargs | cut -f 1 -d" "
}

# kill remaining Qorus processes
while true; do
    pid=`get_qorus_process_pid`
    if [ -z "$pid" ]; then
    	echo "No Qorus processes found. Exiting."
        exit 0
    fi

    echo "Found Qorus process with pid $pid. Killing now."
    kill -9 $pid
    result=$?
    if [ "$result" = "0" ]; then
        echo "Done."
    else
        echo "Failed. Exiting."
        exit 0
    fi
done
