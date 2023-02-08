#!/bin/sh
exec 2>&1

. /opt/qorus/bin/env.sh
QORUS_UID=`cat $QORUS_INIT_STATE_DIR/QORUS_UID`
QORUS_GID=`cat $QORUS_INIT_STATE_DIR/QORUS_GID`

# step down to Qorus user and group before running qorus-core
exec chpst -u :${QORUS_UID}:${QORUS_GID} qorus-core -I ${QORUS_CORE_OPTS}
