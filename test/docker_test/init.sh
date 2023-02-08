#!/bin/bash

set -e

echo "================================"
echo " Qorus Docker Test initializing"
echo "================================"

. /tmp/env.sh

if [ -z "$QORUS_BUILD_DIR" ]; then
    QORUS_BUILD_DIR=build
fi

# do sanity check of qorus bins
check_bins() {
    echo sanity checks of Qorus bins
    qorus -V
    qorus-core -V
    qwf -V
    qsvc -V
    qjob -V
    qdsp -V
    qctl -V
    qbugreport -V
}

# return if systemdb option is set in options file
system_db_is_set() {
    grep -q "^qorus.systemdb" ${OMQ_DIR}/etc/options
}

# return if logdir option is set in options file
logdir_option_is_set() {
    grep -q "^qorus.logdir" ${OMQ_DIR}/etc/options
}

# return if dbparams file contains omq datasource
dbparams_contains_omq_ds() {
    grep -q "^omq=" ${OMQ_DIR}/etc/dbparams
}

# return if DB type set in OMQ_DB_TYPE env var is valid
db_type_is_valid() {
    echo "${OMQ_DB_TYPE}" | grep -q "\(\(my\|pg\)sql\|oracle\)"
}

prepare_test_lists() {
    # tests that must be run while Qorus is down, separated by spaces
    TEST_OFFLINE="SchemaSnapshots SchemaSnapshotsStress ServerSQLInterface"

    # nightly build
    if [ "$QORUS_NIGHTLY" = "1" ]; then
        # blacklisted tests regex, separated by pipe
        TEST_BLACKLIST="QorusBug2400|QorusDebugTest|qdsp|qwf"

    # regular build
    else
        # blacklisted tests regex, separated by pipe
        TEST_BLACKLIST="QorusBug2400|QorusDebugTest|qdsp|qwf|SchemaSnapshotsStress|Issue3530Workflow"
    fi

    echo "export TEST_OFFLINE=\"$TEST_OFFLINE\"" >> /tmp/env.sh
    echo "export TEST_BLACKLIST=\"$TEST_BLACKLIST\"" >> /tmp/env.sh

    # prepare offline test regex
    TEST_OFFLINE2=""
    for test in $TEST_OFFLINE; do
        TEST_OFFLINE2="${test}|$TEST_OFFLINE2"
    done
    # strip trailing |
    TEST_OFFLINE2=${TEST_OFFLINE2%?}

    echo "export TEST_OFFLINE2=\"$TEST_OFFLINE2\"" >> /tmp/env.sh
}

# prepare Qorus system DB schema
prepare_schema() {
    echo "Preparing Qorus system schema"
    schema-tool -Vvf
}

prepare_log_dir() {
    echo "Preparing log dir"
    if [ -z "${QORUS_LOG_DIR}" ]; then
        export QORUS_LOG_DIR=${QORUS_SRC_DIR}/log
    fi
    echo "Log dir set to: ${QORUS_LOG_DIR}"
    echo "export QORUS_LOG_DIR=\"${QORUS_LOG_DIR}\"" >> /tmp/env.sh
    mkdir -p ${QORUS_LOG_DIR}

    if ! logdir_option_is_set; then
        echo "qorus.logdir: ${QORUS_LOG_DIR}" >> ${OMQ_DIR}/etc/options
    fi

    chown -R ${QORUS_UID}:${QORUS_GID} ${QORUS_LOG_DIR}
}

# load job, service etc. files from OMQ_DIR/system directory
load_system_services() {
    echo "Loading system services"
    oload -lR ${OMQ_DIR}/system/*.q*.yaml
}

# load regression test code
load_tests() {
    echo "Loading test code"
    cd ${QORUS_SRC_DIR}/"$QORUS_BUILD_DIR"
    make install-test
}

chown_omq_dir() {
    # make everything owned by Qorus user and group
    chown -R ${QORUS_UID}:${QORUS_GID} ${OMQ_DIR}
}

parse_db_type_from_db_string() {
    OMQ_DB_TYPE=`echo "${OMQ_DB_STRING}" | cut -d: -f1`
}

check_db_string_env_var() {
    parse_db_type_from_db_string
    if [ "${OMQ_DB_TYPE}" = "pgsql" ]; then
        OMQ_DB_TABLESPACE=pg_default
    fi
}

check_db_separate_env_vars() {
    if [ -z "${OMQ_DB_NAME}" ]; then
        echo "Error: Missing database name" >&2
        exit 1
    fi
    if [ -z "${OMQ_DB_TYPE}" ]; then
        echo "Error: Missing database type (possible values: mysql, oracle, pgsql)" >&2
        exit 1
    fi
    if ! db_type_is_valid; then
        echo "Error: Invalid database type (possible values: mysql, oracle, pgsql)" >&2
        exit 1
    fi
    if [ -z "${OMQ_DB_USER}" ]; then
        echo "Error: Missing database user" >&2
        exit 1
    fi
    if [ -z "${OMQ_DB_PASS}" ]; then
        echo "Error: Missing database password" >&2
        exit 1
    fi
    if [ -z "${OMQ_DB_HOST}" ]; then
        OMQ_DB_HOST=localhost
    fi
    if [ -z "${OMQ_DB_ENC}" ]; then
        OMQ_DB_ENC=utf8
    fi
    if [ -z "${OMQ_DB_TABLESPACE}" ]; then
        if [ "${OMQ_DB_TYPE}" = "pgsql" ]; then
            OMQ_DB_TABLESPACE=pg_default
        fi
    fi
}

check_db_env_vars() {
    if [ -z "${OMQ_DB_STRING}" ]; then
        check_db_separate_env_vars
    else
        check_db_string_env_var
    fi
}

check_write_db_tablespace() {
    if [ -n "${OMQ_DB_TABLESPACE}" ]; then
        echo "Writing system DB tablespace to options file: ${OMQ_DIR}/etc/options"
        echo "DB tablespace: '${OMQ_DB_TABLESPACE}'"
        echo "qorus-client.omq-data-tablespace: ${OMQ_DB_TABLESPACE}" >> ${OMQ_DIR}/etc/options
        echo "qorus-client.omq-index-tablespace: ${OMQ_DB_TABLESPACE}" >> ${OMQ_DIR}/etc/options
    fi
}

write_systemdb_option() {
    echo "Writing system DB connection string to options file: ${OMQ_DIR}/etc/options"
    if [ -z "${OMQ_DB_STRING}" ]; then
        systemdb_string="${OMQ_DB_TYPE}:${OMQ_DB_USER}/${OMQ_DB_PASS}@${OMQ_DB_NAME}%${OMQ_DB_HOST}"
    else
        systemdb_string="${OMQ_DB_STRING}"
    fi
    echo "Connection string: '${systemdb_string}'"
    echo "qorus.systemdb: ${systemdb_string}" >> ${OMQ_DIR}/etc/options
}

check_load_omquser() {
    # check variables for omquser datasource
    if [ -n "${OMQUSER_DB_NAME}" -a -n "${OMQUSER_DB_TYPE}" -a -n "${OMQUSER_DB_USER}" -a -n "${OMQUSER_DB_PASS}" ]; then
        if [ -z "${OMQUSER_DB_HOST}" ]; then
            OMQUSER_DB_HOST=localhost
        fi

        omquser_string="${OMQUSER_DB_TYPE}:${OMQUSER_DB_USER}/${OMQUSER_DB_PASS}@${OMQUSER_DB_NAME}%${OMQUSER_DB_HOST}"

    elif [ -n "${OMQUSER_DB_STRING}" ]; then
        omquser_string="${OMQUSER_DB_STRING}"

    else
        # use same DB like system
        if [ -z "${OMQ_DB_STRING}" ]; then
            omquser_string="${OMQ_DB_TYPE}:${OMQ_DB_USER}/${OMQ_DB_PASS}@${OMQ_DB_NAME}%${OMQ_DB_HOST}"
        else
            omquser_string="${OMQ_DB_STRING}"
        fi
    fi

    echo "Creating omquser DB connection: '${omquser_string}'"
    qdp db{datasource=${systemdb_string}}/connections create name=omquser,description=omquser,url=db://${omquser_string},enabled=1,connection_type=DATASOURCE
}

do_env_var_config() {
    echo "Checking environment variables for system DB configuration"

    check_db_env_vars
    check_write_db_tablespace
    write_systemdb_option
}

db_config() {
    echo "Configuring Qorus system DB"

    if system_db_is_set; then
        echo "System DB already configured in options file"
    else
        echo "Warning: systemdb option is not set"

        if [ ! -e ${OMQ_DIR}/etc/dbparams ]; then
            echo "Warning: dbparams file is missing"
            do_env_var_config
        elif ! dbparams_contains_omq_ds; then
            echo "Warning: dbparams file does not contain omq datasource"
            do_env_var_config
        else
            echo "System DB configured in dbparams file"
        fi
    fi
}

do_init_steps() {
    # prepare the log dir
    prepare_log_dir

    # make OMQ_DIR owned by qorus user and group
    chown_omq_dir

    # configure database connection
    db_config

    # prepare DB schema
    prepare_schema

    # check qorus bins
    check_bins

    # load system jobs, services etc.
    load_system_services

    # load the omquser datasource; must happen before tests are loaded
    check_load_omquser

    # load test code
    load_tests

    prepare_test_lists

    # again make sure OMQ_DIR is owned by qorus user and group
    chown_omq_dir
}

do_init_steps

echo "================================="
echo " Qorus Docker Test init complete"
echo "================================="; echo
