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
export LD_LIBRARY_PATH=${ORACLE_INSTANT_CLIENT}:${QORUS_INSTALL_PREFIX}/lib:${LD_LIBRARY_PATH}
export PYTHONPATH=${OMQ_DIR}/python:${OMQ_DIR}/user/python/lib/python3.10/site-packages
export JAVA_HOME=/usr/lib/jvm/default-jvm
export PATH=${QORUS_INSTALL_PREFIX}/bin:${JAVA_HOME}/bin:${OMQ_DIR}/bin:${OMQ_DIR}/user/python/bin:$PATH
export FREETDSCONF=$OMQ_DIR/etc/freetds.conf
export QORE_LIBRARY=${QORUS_INSTALL_PREFIX}/lib/libqore.so
