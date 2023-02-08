#!/bin/sh

set -e
set -x

prep_image() {
    ENV_FILE=/tmp/env.sh

    # setup QORUS_SRC_DIR env var
    cwd=`pwd`
    if [ "${QORUS_SRC_DIR}" = "" ]; then
        if [ -d "$cwd/qlib-qorus" ] || [ -e "$cwd/bin/qctl" ] || [ -e "$cwd/cmake/QorusMacros.cmake" ] || [ -e "$cwd/lib/qorus.ql" ]; then
            QORUS_SRC_DIR=$cwd
        else
            QORUS_SRC_DIR=$WORKDIR/qorus
        fi
    fi

    # check for final branches
    export FINAL_BRANCH=`${QORUS_SRC_DIR}/test/docker_test/final_branch.sh`

    echo "export QORE_LIBRARY=/usr/lib/libqore.so" >> ${ENV_FILE}

    echo "export QORUS_SRC_DIR=${QORUS_SRC_DIR}" >> ${ENV_FILE}

    echo "export QORUS_UID=1000" >> ${ENV_FILE}
    echo "export QORUS_GID=1000" >> ${ENV_FILE}

    echo "export QORUS_DEBUG_CLIENT=1" >> ${ENV_FILE}

    # set $OMQ_DIR
    . ${ENV_FILE}

    # set PYTHONPATH using $OMQ_DIR
    echo "export PYTHONPATH=${OMQ_DIR}/python:${OMQ_DIR}/user/python/lib/python3.10/site-packages" >> ${ENV_FILE}

    # re-read env vars
    . ${ENV_FILE}

    # source postgres lib
    . ${QORUS_SRC_DIR}/test/docker_test/postgres_lib.sh
    if [ -z "${ORACLE_SID}" ]; then
        # start postgres and setup up env vars
        if [ -n "${DOCKER_NETWORK}" ]; then
            apk add --no-cache postgresql
            setup_postgres_on_rippy
        else
            start_postgres
        fi
    fi

    export MAKE_JOBS=6

    # build Qorus and install
    echo && echo "-- building Qorus --"
    cd ${QORUS_SRC_DIR}
    if [ -z "$QORUS_BUILD_DIR" ]; then
        QORUS_BUILD_DIR=build
    fi
    if [ ! -d "$QORUS_BUILD_DIR" ]; then
        mkdir "$QORUS_BUILD_DIR"
    fi
    cd "$QORUS_BUILD_DIR"
    if [ "$FINAL_BRANCH" = "1" ]; then
        cmake .. -DCMAKE_BUILD_TYPE=release
    else
        cmake .. -DCMAKE_BUILD_TYPE=debug
    fi
    make
    make install

    # prepare OMQ_DIR and log dir
    mkdir -p ${OMQ_DIR}/releases ${OMQ_DIR}/user
    mv ${OMQ_DIR}/etc/options.example ${OMQ_DIR}/etc/options

    # generate https cert
    openssl req \
            -x509 \
            -newkey rsa:4096 \
            -sha384 \
            -nodes \
            -keyout ${OMQ_DIR}/etc/key.pem \
            -out ${OMQ_DIR}/etc/cert.pem \
            -subj '/CN=localhost' \
            -days 365

    # add some options for testing
    echo "qorus.rbac-security: true" >> ${OMQ_DIR}/etc/options
    echo "qorus.debug-system: true" >> ${OMQ_DIR}/etc/options
    echo "qorus.debug-qorus-internals: true" >> ${OMQ_DIR}/etc/options
    echo "qorus.http-server: 8001" >> ${OMQ_DIR}/etc/options
    echo "qorus.http-secure-server: 8011" >> ${OMQ_DIR}/etc/options
    echo "qorus.http-secure-certificate: ${OMQ_DIR}/etc/cert.pem" >> $OMQ_DIR/etc/options
    echo "qorus.http-secure-private-key: ${OMQ_DIR}/etc/key.pem" >> $OMQ_DIR/etc/options
    echo "qorus-client.allow-test-execution: true" >> ${OMQ_DIR}/etc/options
    echo "qorus.audit: *" >> ${OMQ_DIR}/etc/options
    echo "qorus.allow-node-overcommit-percent: 50" >> ${OMQ_DIR}/etc/options
    if [ -f "${QORUS_SRC_DIR}/test/dev-modules/TestUserConnectionProvider.qm" ]; then
        echo "qorus.connection-modules: ${QORUS_SRC_DIR}/test/dev-modules/TestUserConnectionProvider.qm" >> $OMQ_DIR/etc/options
    fi
    if [ -n "${OMQ_SYSTEMDB}" ]; then
        echo "qorus.systemdb: ${OMQ_SYSTEMDB}"
    fi

    # temporary options
    echo "qorus.unsupported-creator-api: true" >> ${OMQ_DIR}/etc/options

    # prepare release file
    cd ${QORUS_SRC_DIR}
    VERSION=`./get-version.sh | sed 's/ *$//'`
    LOADING_FILE="${OMQ_DIR}/releases/qorus-$VERSION.qrf"
    LOAD_DATA_MODEL=`cat ${OMQ_DIR}/qlib/QorusVersion.qm | grep "const load_datamodel" | cut -f2 -d\" | sed 's/ *$//'`

    cd ${OMQ_DIR}
    echo "verify-load-schema ${LOAD_DATA_MODEL}" > ${LOADING_FILE}
    find system -name "*.qgroup.yaml" -exec echo load {} >> $LOADING_FILE \;
    find system -name "*.qsd.yaml" -exec echo load {} >> $LOADING_FILE \;
    find system -name "*.qjob.yaml" -exec echo load {} >> $LOADING_FILE \;

    # add Qorus user and group
    if ! grep -q "^qorus:x:${QORUS_GID}" /etc/group; then
        addgroup -g ${QORUS_GID} qorus
    fi
    if ! grep -q "^qorus:x:${QORUS_UID}" /etc/passwd; then
        adduser -S -u ${QORUS_UID} -D -G qorus -s /bin/bash qorus
    fi
}

if [ "${SKIP_QORUS_TESTS}" = "yes" ]; then
    echo skipping Qorus build
else
    prep_image
fi
