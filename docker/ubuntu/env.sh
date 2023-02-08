#!/bin/sh

export QORUS_ALLOW_ROOT=1
export OMQ_DIR=/opt/qorus
export QORUS_INIT_STATE_DIR=${OMQ_DIR}/init
export QORUS_INSTALL_PREFIX=/opt
export QORE_INCLUDE_DIR=${OMQ_DIR}/qlib
export QORE_MODULE_DIR=${OMQ_DIR}/qlib:${OMQ_DIR}/user/modules
export QORE_DATA_PROVIDERS=QorusDataProviders
export QORE_CONNECTION_PROVIDERS=QorusConnectionProvider
export QORE_DATASOURCE_PROVIDERS=QorusDatasourceProvider
export QORE_FILE_LOCATION_HANDLERS=QorusResourceFileLocationHandler
export ORACLE_INSTANT_CLIENT=/usr/lib/oracle
export ORACLE_HOME=${ORACLE_INSTANT_CLIENT}
export TNS_ADMIN=${ORACLE_INSTANT_CLIENT}
export PYTHONPATH=${OMQ_DIR}/python:${OMQ_DIR}/user/python/local/lib/python3.10/dist-packages
export PATH=${QORUS_INSTALL_PREFIX}/bin:${OMQ_DIR}/bin:${OMQ_DIR}/user/python/bin:$PATH
export FREETDSCONF=$OMQ_DIR/etc/freetds.conf

# get CPU architecture
arch=`uname -m`
if [ "$arch" = "aarch64" ]; then
    export LD_LIBRARY_PATH=${ORACLE_INSTANT_CLIENT}:${QORUS_INSTALL_PREFIX}/lib:${QORUS_INSTALL_PREFIX}/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH}
    export QORE_LIBRARY=/opt/lib/aarch64-linux-gnu/libqore.so
else
    export LD_LIBRARY_PATH=${ORACLE_INSTANT_CLIENT}:${QORUS_INSTALL_PREFIX}/lib:${QORUS_INSTALL_PREFIX}/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}
    export QORE_LIBRARY=/opt/lib/x86_64-linux-gnu/libqore.so
fi

