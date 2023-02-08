#!/bin/bash
set -e

. /opt/qorus/bin/env.sh

qorus_uid_gid_files_exist() {
    [ -e "${QORUS_INIT_STATE_DIR}/QORUS_UID" ] && [ -e "${QORUS_INIT_STATE_DIR}/QORUS_GID" ]
}

qorus_systemdb_is_set() {
    grep -q "^qorus\.systemdb" ${OMQ_DIR}/etc/options
}

qorus_schema_prepared() {
    [ -e "${QORUS_INIT_STATE_DIR}/schema_prepared" ]
}

qorus_network_key_readable() {
    [ -e "${OMQ_DIR}/etc/network.key" ] && [ -r "${OMQ_DIR}/etc/network.key" ]
}

qorus_init_finished() {
    [ -e "${QORUS_INIT_STATE_DIR}/init_finished" ]
}

wait_for_init_finished() {
    echo "Waiting for Qorus initialization to finish"
    while true; do
        if qorus_init_finished; then
            if qorus_uid_gid_files_exist && qorus_systemdb_is_set && qorus_schema_prepared && qorus_network_key_readable; then
                break
            fi
        fi
        sleep 1
    done
    echo "Qorus initialization finished"
}

qorus_normal_start() {
    /opt/qorus/bin/init.sh
    if [ "$QORUS_MASTER_OPTS" != "" ]; then
        echo "Launching qorus with options: ${QORUS_MASTER_OPTS}"
    fi
    exec runsv /etc/service/qorus
}

qorus_init_only_start() {
    echo "Doing initialization only"
    /opt/qorus/bin/init.sh
}

qorus_no_init_start() {
    echo "Starting Qorus (no-init)"
    if [ "$QORUS_INDEPENDENT_MODE" = "1" ]; then
        QORUS_MASTER_OPTS="-I ${QORUS_MASTER_OPTS}"
        echo "export QORUS_MASTER_OPTS=\"${QORUS_MASTER_OPTS}\"" >> /opt/qorus/bin/env.sh
    fi

    /opt/qorus/bin/min_init.sh

    if [ "$QORUS_MASTER_OPTS" != "" ]; then
        echo "Launching qorus with options: ${QORUS_MASTER_OPTS}"
    fi
    if [ "$QORUS_DUMB_INIT" = "1" ]; then
        QORUS_UID=`cat $QORUS_INIT_STATE_DIR/QORUS_UID`
        QORUS_GID=`cat $QORUS_INIT_STATE_DIR/QORUS_GID`
        exec 2>&1
        exec chpst -u :${QORUS_UID}:${QORUS_GID} dumb-init qorus daemon-mode=0 ${QORUS_MASTER_OPTS}
    else
        exec runsv /etc/service/qorus
    fi
}

qorus_core_start() {
    echo "Starting qorus-core"
    wait_for_init_finished
    sleep 5

    /opt/qorus/bin/min_init.sh

    if [ "$QORUS_CORE_OPTS" != "" ]; then
        echo "Launching qorus-core with options: ${QORUS_CORE_OPTS}"
    fi
    if [ "$QORUS_DUMB_INIT" = "1" ]; then
        QORUS_UID=`cat $QORUS_INIT_STATE_DIR/QORUS_UID`
        QORUS_GID=`cat $QORUS_INIT_STATE_DIR/QORUS_GID`
        exec 2>&1
        exec chpst -u :${QORUS_UID}:${QORUS_GID} dumb-init qorus-core -I ${QORUS_CORE_OPTS}
    else
        exec runsv /etc/service/qorus-core
    fi
}

launch_qorus() {
    if [ "$QORUS_INIT_ONLY" = "1" ]; then
        qorus_init_only_start
    elif [ "$QORUS_NO_INIT" = "1" ]; then
        qorus_no_init_start
    elif [ "$QORUS_CORE_ONLY" = "1" ]; then
        qorus_core_start
    else
        qorus_normal_start
    fi
}

launch_stateless_service() {
    # init must be complete here
    /opt/qorus/bin/min_init.sh

    service="$1"

    if [ "$QORUS_DUMB_INIT" = "1" ]; then
        QORUS_UID=`cat $QORUS_INIT_STATE_DIR/QORUS_UID`
        QORUS_GID=`cat $QORUS_INIT_STATE_DIR/QORUS_GID`
        exec 2>&1
        exec chpst -u :${QORUS_UID}:${QORUS_GID} dumb-init qsvc -I $2
    else
        exec su qorus -c ". /opt/qorus/bin/env.sh; qsvc -I $service"
    fi
}

case "$1" in
    "bash")
        exec "$@"
    ;;
    "sh")
        exec "$@"
    ;;
    "stateless-service")
        launch_stateless_service "$2"
    ;;
    "")
        launch_qorus
    ;;
    *)
        launch_qorus
    ;;
esac
