#!/bin/sh
exec 2>&1

. /opt/qorus/bin/env.sh
QORUS_UID=`cat $QORUS_INIT_STATE_DIR/QORUS_UID`
QORUS_GID=`cat $QORUS_INIT_STATE_DIR/QORUS_GID`

# step down to Qorus user and group before running Qorus
exec chpst -u :${QORUS_UID}:${QORUS_GID} qorus --log-level=ALL --debug-system daemon-mode=0 ${QORUS_MASTER_OPTS}
