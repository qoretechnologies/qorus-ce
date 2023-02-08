#!/bin/bash

# The following script initializes the basic Qorus environment if it has not been
# initialized yet. The state of initialization is kept in $QORUS_INIT_STATE_DIR.

set -e

echo "==========================="
echo " Qorus Docker initializing"
echo "==========================="

. /opt/qorus/bin/env.sh

if [ "${FORCE_INIT_STEPS}" = "1" ]; then
    FORCE_LOAD_SYSTEM_SERVICES=1
fi

# setup time zone in container
setup_tz() {
    echo "Setting up time zone"
    if [ -z "${QORUS_TZ}" -a -z "${TZ}" ]; then
        echo TZ / QORUS_TZ env vars not set\; running under UTC
        return
    fi

    if [ -n "${QORUS_TZ}" ]; then
        tz="${QORUS_TZ}"
        tzfile=/usr/share/zoneinfo/"${QORUS_TZ}"
    else
        tz="${TZ}"
        tzfile=/usr/share/zoneinfo/"${TZ}"
    fi
    if [ ! -f "${tzfile}" ]; then
        echo time zone file $tzfile: does not exist\; running under UTC
        return
    fi

    echo ${tz} > /etc/timezone
    rm -f /etc/localtime
    ln -s "${tzfile}" /etc/localtime

    echo "set time zone to ${tz}"
    date
}

##########################
# Qorus directories setup
##########################

# return if OMQ_DIR/etc dir is empty
etc_dir_empty() {
    contents=`ls $OMQ_DIR/etc | xargs`
    [ -z "$contents" ]
}

# return whether a dir is owned by qorus
dir_owned_by_qorus() {
    dir_base=`dirname $1`
    dir_name=`basename $1`
    dir_uid=`ls $dir_base -n | grep " $dir_name\$" | xargs | cut -d' ' -f3`
    dir_gid=`ls $dir_base -n | grep " $dir_name\$" | xargs | cut -d' ' -f4`
    [ "$dir_uid" = "$QORUS_UID" ] && [ "$dir_gid" = "$QORUS_GID" ]
}

# change ownership of a directory to qorus
chown_qorus_dir() {
    if [ "$1" != "${OMQ_DIR}/etc" ]; then
        # check ownership first; if not the recursive ownership change can be very slow
        dir="$1"
        if dir_owned_by_qorus "${dir}"; then
            echo "directory '$1' already has ownership '${QORUS_UID}:${QORUS_GID}'"
            return
        fi
    fi
    echo "Changing ownership of '$1' to '${QORUS_UID}:${QORUS_GID}'"
    if ! chown -R ${QORUS_UID}:${QORUS_GID} $1; then
        echo "Error: Failed changing ownership of '$1' to qorus. Cannot continue." >&2
        exit 1
    fi
}

# chown necessary dirs for Qorus to Qorus user and group
chown_qorus_dirs() {
    if [ ! -d ${OMQ_DIR}/releases ]; then
        mkdir ${OMQ_DIR}/releases
    fi
    qorus_dirs="etc log user releases"
    for dir in ${qorus_dirs}; do
        chown_qorus_dir "${OMQ_DIR}/${dir}"
    done
    echo "Changing ownership of OMQ_DIR to '${QORUS_UID}:${QORUS_GID}'"
    chown ${QORUS_UID}:${QORUS_GID} ${OMQ_DIR}
}

# fill OMQ_DIR/etc directory with defaults, if it's empty
fill_etc_dir() {
    if etc_dir_empty; then
        cp -r ${OMQ_DIR}/etc.default/* ${OMQ_DIR}/etc/
        return
    fi

    # fill in missing default etc files
    default_etc_files=`ls $OMQ_DIR/etc.default`
    for etcfile in ${default_etc_files}; do
        # always copy "images"
        if [ ! -e "${OMQ_DIR}/etc/${etcfile}" -o "${etcfile}" = "images" ]; then
            if [ -d "${OMQ_DIR}/etc.default/${etcfile}" ]; then
                echo "Copying default directory template '${etcfile}' to OMQ_DIR/etc directory"
                cp -r ${OMQ_DIR}/etc.default/${etcfile} ${OMQ_DIR}/etc/
            else
                echo "Copying default file template '${etcfile}' to OMQ_DIR/etc directory"
                cp ${OMQ_DIR}/etc.default/${etcfile} ${OMQ_DIR}/etc/
            fi

        fi
    done
}

#############################
# Qorus user and group setup
#############################

# default values for pre-created qorus account
DEFAULT_QORUS_UID=1000
DEFAULT_QORUS_GID=1000

# return owner UID of a directory in OMQ_DIR, param $1 ... dir name
find_omqdir_uid() {
    ls -l -n ${OMQ_DIR} | grep -e " ${1}\$" | xargs | cut -f3 -d' '
}

# return owner GID of a directory in OMQ_DIR, param $1 ... dir name
find_omqdir_gid() {
    ls -l -n ${OMQ_DIR} | grep -e " ${1}\$" | xargs | cut -f4 -d' '
}

# return if qorus user already exists
qorus_user_exists() {
    grep -q qorus /etc/passwd
}

# return if qorus group already exists
qorus_group_exists() {
    grep -q qorus /etc/group
}

# check that Qorus UID and GID are integers
check_qorus_uid_gid_integer() {
    if [[ "${QORUS_UID}" =~ ^[0-9]+$ ]]; then
        : # ok
    else
        echo "Error: Qorus UID is not an integer." >&2
        exit 1
    fi

    if [[ "${QORUS_GID}" =~ ^[0-9]+$ ]]; then
        : # ok
    else
        echo "Error: Qorus GID is not an integer." >&2
        exit 1
    fi
}

# check that Qorus UID and GID are non-root IDs
check_qorus_uid_gid_nonroot() {
    if [ "${QORUS_UID}" = "0" ]; then
        echo "Error: Qorus UID is set to 0 (root). This is not allowed for security reasons." >&2
        exit 1
    fi
    if [ "${QORUS_GID}" = "0" ]; then
        echo "Error: Qorus GID is set to 0 (root). This is not allowed for security reasons." >&2
        exit 1
    fi
}

configure_uid_gid_vars() {
    echo "Configuring user and group under which Qorus will run"

    # find out UIDs and GIDs of OMQ_DIR directories
    etc_uid=`find_omqdir_uid etc`
    log_uid=`find_omqdir_uid log`
    user_uid=`find_omqdir_uid user`

    etc_gid=`find_omqdir_gid etc`
    log_gid=`find_omqdir_gid log`
    user_gid=`find_omqdir_gid user`

    # info prints
    echo "QORUS_UID: '${QORUS_UID}'"
    echo "QORUS_GID: '${QORUS_GID}'"
    echo "OMQ_DIR/etc UID: '${etc_uid}', GID: '${etc_gid}'"
    echo "OMQ_DIR/log UID: '${log_uid}', GID: '${log_gid}'"
    echo "OMQ_DIR/user UID: '${user_uid}', GID: '${user_gid}'"

    # check if QORUS_UID and QORUS_GID env vars are set
    if [ -n "${QORUS_UID}" ]; then
        if [ "${QORUS_GID}" = "" ]; then
            echo "Error: Qorus user defined, but Qorus group not. Both QORUS_UID and QORUS_GID environment variables have to be set." >&2
            exit 1
        fi
        echo "Qorus UID and GID set from environment variables - ${QORUS_UID}:${QORUS_GID}"
    elif [ -n "${QORUS_GID}" ]; then
        if [ "${QORUS_UID}" = "" ]; then
            echo "Error: Qorus group defined, but Qorus user not. Both QORUS_UID and QORUS_GID environment variables have to be set." >&2
            exit 1
        fi
        echo "Qorus UID and GID set from environment variables - ${QORUS_UID}:${QORUS_GID}"

    # check if the QORUS_UID and QORUS_GID files already exist
    elif [ -e "${QORUS_INIT_STATE_DIR}/QORUS_UID" ] && [ -e "${QORUS_INIT_STATE_DIR}/QORUS_GID" ]; then
        echo "Qorus UID and GID files exist in the init folder. Using them to set QORUS_UID and QORUS_GID."
        QORUS_UID=`cat $QORUS_INIT_STATE_DIR/QORUS_UID`
        QORUS_GID=`cat $QORUS_INIT_STATE_DIR/QORUS_GID`

    # check if there are mounted OMQ_DIR directories under different user than root
    elif [ "${etc_uid}" != "0" ] || [ "${etc_gid}" != "0" ]; then
        QORUS_UID=${etc_uid}
        QORUS_GID=${etc_gid}
        echo "Qorus UID and GID set to match owner of the OMQ_DIR/etc directory - ${QORUS_UID}:${QORUS_GID}"
    elif [ "${log_uid}" != "0" ] || [ "${log_gid}" != "0" ]; then
        QORUS_UID=${log_uid}
        QORUS_GID=${log_gid}
        echo "Qorus UID and GID set to match owner of the OMQ_DIR/log directory - ${QORUS_UID}:${QORUS_GID}"
    elif [ "${user_uid}" != "0" ] || [ "${user_gid}" != "0" ]; then
        QORUS_UID=${user_uid}
        QORUS_GID=${user_gid}
        echo "Qorus UID and GID set to match owner of the OMQ_DIR/user directory - ${QORUS_UID}:${QORUS_GID}"

    # otherwise use defaults
    else
        QORUS_UID=${DEFAULT_QORUS_UID}
        QORUS_GID=${DEFAULT_QORUS_GID}
        echo "Using default Qorus user and group IDs - ${QORUS_UID}:${QORUS_GID}"
    fi

    # check that both UID and GID are integers
    check_qorus_uid_gid_integer

    # check that both UID and GID are not 0 (root)
    check_qorus_uid_gid_nonroot
}

write_qorus_uid_gid_files() {
    # make sure that init dir is owned by qorus
    if ! dir_owned_by_qorus ${QORUS_INIT_STATE_DIR}; then
        chown_qorus_dir ${QORUS_INIT_STATE_DIR}
    fi

    # write the UID and GID files if they don't exist or their content is incorrect
    if [ ! -e "${QORUS_INIT_STATE_DIR}/QORUS_UID" ] || [ "$QORUS_UID" != "`cat $QORUS_INIT_STATE_DIR/QORUS_UID`" ]; then
        printf "${QORUS_UID}" > ${QORUS_INIT_STATE_DIR}/QORUS_UID
        chmod 644 ${QORUS_INIT_STATE_DIR}/QORUS_UID
        echo "Written Qorus UID to ${QORUS_INIT_STATE_DIR}/QORUS_UID"
    fi
    if [ ! -e "${QORUS_INIT_STATE_DIR}/QORUS_GID" ] || [ "$QORUS_GID" != "`cat $QORUS_INIT_STATE_DIR/QORUS_GID`" ]; then
        printf "${QORUS_GID}" > ${QORUS_INIT_STATE_DIR}/QORUS_GID
        chmod 644 ${QORUS_INIT_STATE_DIR}/QORUS_GID
        echo "Written Qorus GID to ${QORUS_INIT_STATE_DIR}/QORUS_GID"
    fi
}

# add Qorus user and group if they don't exist yet and are different from root
add_qorus_user_group() {
    if [ "${QORUS_GID}" != "0" ] && ! qorus_group_exists; then
        if grep -q ${QORUS_GID} /etc/group; then
            echo "Updating qorus group (GID: ${QORUS_GID})"
            sed -i -E "s/[^:]+:(.*:${QORUS_GID})/qorus:\1/" /etc/group
        else
            echo "Adding qorus group (GID: ${QORUS_GID})"
            addgroup -g ${QORUS_GID} qorus
        fi
    fi
    if [ "${QORUS_UID}" != "0" ] && ! qorus_user_exists; then
        if grep -q ${QORUS_UID} /etc/passwd; then
            echo "Updating qorus user (UID: ${QORUS_UID})"
            sed -i -E "s/[^:]+:(.*:${QORUS_UID})/qorus:\1/" /etc/passwd
        else
            echo "Adding qorus user (UID: ${QORUS_UID})"
            adduser -S -u ${QORUS_UID} -G qorus -D -H -h ${OMQ_DIR} -s /bin/bash qorus
            echo "if [ -f ${OMQ_DIR}/env.sh ]; then . ${OMQ_DIR}/env.sh; fi" >> ${OMQ_DIR}/.profile
        fi
    fi
}

####################
# Qorus HTTPS setup
####################

# return if Qorus HTTPS cert option is set
https_cert_option_is_set() {
    grep -E -q "^qorus.(http-secure-certificate|http-secure-server.*cert=)" ${OMQ_DIR}/etc/options
}

# return if Qorus HTTPS cert private key option is set
https_privkey_option_is_set() {
    grep -E -q "^qorus.(http-secure-private-key|http-secure-server.*key=)" ${OMQ_DIR}/etc/options
}

# return if Qorus HTTPS server option is set
https_server_option_is_set() {
    grep -q "^qorus.http-secure-server" ${OMQ_DIR}/etc/options
}

# return if HTTPS cert and private key files exist in OMQ_DIR/etc directory
https_cert_key_exist() {
    test -e "${OMQ_DIR}/etc/cert.pem" && test -e "${OMQ_DIR}/etc/key.pem"
}

# check if HTTPS options are incorrectly set
check_https_options() {
    if https_cert_option_is_set; then
        if ! https_privkey_option_is_set; then
            echo "Error: HTTPS certificate option is set but private key option is not. Both are required." >&2
            exit 1
        fi
        if ! https_server_option_is_set; then
            echo "Error: HTTPS certificate and certificate private key options are set but HTTPS server port is not. All are required." >&2
            exit 1
        fi
    else
        if https_privkey_option_is_set; then
            echo "Error: HTTPS certificate private key option is set but certificate option is not. Both are required." >&2
            exit 1
        fi

        if https_server_option_is_set; then
            echo "Error: HTTPS server port option is set but certificate options are not. All are required." >&2
            exit 1
        fi
    fi
}

# generate new HTTPS cert and private key in OMQ_DIR/etc directory
generate_https_cert() {
    openssl req \
        -x509 \
        -newkey rsa:4096 \
        -sha384 \
        -nodes \
        -keyout ${OMQ_DIR}/etc/key.pem \
        -out ${OMQ_DIR}/etc/cert.pem \
        -subj '/CN=localhost' \
        -days 365
}

# write Qorus HTTPS options to the options file
write_https_options() {
    echo "Using HTTPS cert file \$OMQ_DIR/etc/cert.pem and key file \$OMQ_DIR/etc/key.pem"
    # bind on all interfaces (IPv6 and IPv4)
    echo "qorus.http-secure-server: 8011" >> ${OMQ_DIR}/etc/options
    echo "qorus.http-secure-certificate: \$OMQ_DIR/etc/cert.pem" >> ${OMQ_DIR}/etc/options
    echo "qorus.http-secure-private-key: \$OMQ_DIR/etc/key.pem" >> ${OMQ_DIR}/etc/options
}

# prepare Qorus for HTTPS
prepare_https() {
    # check if HTTPS options are incorrectly set
    check_https_options

    # if options are already set, just print them and return
    if https_cert_option_is_set; then
        echo "HTTPS options are already set:"
        grep -e "^qorus.http-secure-server" -e "^qorus.http-secure-certificate" -e "^qorus.http-secure-private-key" ${OMQ_DIR}/etc/options
        return
    fi

    # generate HTTPS cert and key if they don't exist
    if ! https_cert_key_exist; then
        generate_https_cert
    fi

    write_https_options
}

############################
# Qorus DB tablespace setup
############################

# return if Qorus DB tablespace option is set
db_tablespace_set() {
    grep -q "^qorus-client.omq-data-tablespace" ${OMQ_DIR}/etc/options
}

# return if Qorus DB tablespace option is set and matches $OMQ_DB_TABLESPACE
db_tablespace_matches() {
    grep "^qorus-client.omq-data-tablespace" ${OMQ_DIR}/etc/options | grep -q "${OMQ_DB_TABLESPACE}"
}

# write DB tablespace options to the options file
do_write_db_tablespace() {
    echo "Writing system DB tablespace to options file: ${OMQ_DIR}/etc/options"
    echo "DB tablespace: '${OMQ_DB_TABLESPACE}'"
    echo "qorus-client.omq-data-tablespace: ${OMQ_DB_TABLESPACE}" >> ${OMQ_DIR}/etc/options
    echo "qorus-client.omq-index-tablespace: ${OMQ_DB_TABLESPACE}" >> ${OMQ_DIR}/etc/options
}

check_write_db_tablespace() {
    if [ -n "${OMQ_DB_TABLESPACE}" ]; then
        if ! db_tablespace_set; then
            do_write_db_tablespace
        elif ! db_tablespace_matches; then
            do_write_db_tablespace
        fi
    fi
}

####################
# Qorus DB setup
####################

# return if systemdb option is set in options file
systemdb_option_set() {
    grep -q "^qorus\.systemdb" ${OMQ_DIR}/etc/options
}

# parse qorus.systemdb option string into $SYSTEMDB_STRING
parse_systemdb_option() {
    SYSTEMDB_STRING=`grep -e "^qorus.systemdb" $OMQ_DIR/etc/options | tail -n 1 | sed 's/qorus.systemdb://' | xargs`
}

# return if dbparams file contains omq datasource
dbparams_contains_omq_ds() {
    grep -q "^omq=" ${OMQ_DIR}/etc/dbparams
}

# return if DB type set in OMQ_DB_TYPE env var is valid
db_type_is_valid() {
    echo "${OMQ_DB_TYPE}" | grep -q "\(\(my\|pg\)sql\|oracle\)"
}

# check if DB environment variables are set
check_db_env_vars() {
    if [ -z ${OMQ_DB_NAME} ]; then
        echo "Error: Missing database name" >&2
        exit 1
    fi
    if [ -z ${OMQ_DB_TYPE} ]; then
        echo "Error: Missing database type (possible values: mysql, oracle, pgsql)" >&2
        exit 1
    fi
    if ! db_type_is_valid; then
        echo "Error: Invalid database type (possible values: mysql, oracle, pgsql)" >&2
        exit 1
    fi
    if [ -z ${OMQ_DB_USER} ]; then
        echo "Error: Missing database user" >&2
        exit 1
    fi
    if [ -z ${OMQ_DB_PASS} ]; then
        echo "Error: Missing database password" >&2
        exit 1
    fi
    if [ -z ${OMQ_DB_HOST} ]; then
        OMQ_DB_HOST=localhost
    fi
    if [ -z ${OMQ_DB_ENC} ]; then
        OMQ_DB_ENC=utf8
    fi
    if [ -z ${OMQ_DB_TABLESPACE} ]; then
        if [ "${OMQ_DB_TYPE}" = "pgsql" ]; then
            OMQ_DB_TABLESPACE=pg_default
        fi
    fi
}

# write qorus.systemdb option to the options file
write_systemdb_option() {
    echo "Writing system DB connection string to options file: ${OMQ_DIR}/etc/options"
    SYSTEMDB_STRING="${OMQ_DB_TYPE}:${OMQ_DB_USER}/${OMQ_DB_PASS}@${OMQ_DB_NAME}(${OMQ_DB_ENC})%${OMQ_DB_HOST}"
    redacted_str="${OMQ_DB_TYPE}:${OMQ_DB_USER}/<REDACTED>@${OMQ_DB_NAME}(${OMQ_DB_ENC})%${OMQ_DB_HOST}"
    echo "Connection string: '${redacted_str}'"
    echo "qorus.systemdb: ${SYSTEMDB_STRING}" >> ${OMQ_DIR}/etc/options
}

db_env_var_config() {
    echo "Checking environment variables for system DB configuration"

    check_db_env_vars
    check_write_db_tablespace
    write_systemdb_option
}

db_config() {
    echo "Configuring Qorus system DB"

    if systemdb_option_set; then
        echo "System DB already configured in options file"
        parse_systemdb_option # needed for omquser datasource later
    else
        echo "Warning: systemdb option is not set"

        if [ ! -e ${OMQ_DIR}/etc/dbparams ]; then
            echo "Warning: dbparams file is missing"
            db_env_var_config
        elif ! dbparams_contains_omq_ds; then
            echo "Warning: dbparams file does not contain omq datasource"
            db_env_var_config
        else
            echo "System DB configured in dbparams file"
        fi
    fi
}

#####################
# Qorus schema setup
#####################

# prepare Qorus system DB schema
prepare_schema() {
    if [ "$QORUS_FORCE_CHECK_SCHEMA" = "1" ]; then
        echo "Preparing Qorus system schema (force flag set)"
        schema-tool -Vf
    else
        echo "Preparing Qorus system schema"
        schema-tool -V
    fi
    touch ${QORUS_INIT_STATE_DIR}/schema_prepared
}

#################################
# Qorus omquser connection setup
#################################

# oload omquser connection to Qorus
check_load_omquser() {
    # return if omquser connection already oloaded
    test -e ${QORUS_INIT_STATE_DIR}/omquser_oloaded && return

    # check variables for omquser datasource
    if [ -n "${OMQUSER_DB_NAME}" -a -n "${OMQUSER_DB_TYPE}" -a -n "${OMQUSER_DB_USER}" -a -n "${OMQUSER_DB_PASS}" ]; then
        if [ -z ${OMQUSER_DB_HOST} ]; then
            OMQUSER_DB_HOST=localhost
        fi
        if [ -z ${OMQUSER_DB_ENC} ]; then
            OMQUSER_DB_ENC=utf8
        fi

        omquser_string="${OMQUSER_DB_TYPE}:${OMQUSER_DB_USER}/${OMQUSER_DB_PASS}@${OMQUSER_DB_NAME}(${OMQUSER_DB_ENC})%${OMQUSER_DB_HOST}"
    else
        # use same DB like system
        omquser_string="${SYSTEMDB_STRING}"
    fi
    redacted_str=`echo -n "$omquser_string" | sed 's/\/.*@/\/<REDACTED>@/'`

    echo "Loading omquser DB connection: '${redacted_str}'"
    echo "omquser = (desc = omquser, url = db://${omquser_string})" > /tmp/omquser.qconn
    oload -lRv /tmp/omquser.qconn
    rm -f /tmp/omquser.qconn
    touch ${QORUS_INIT_STATE_DIR}/omquser_oloaded
}

######################
# Qorus service setup
######################

# load job, service etc. files from OMQ_DIR/system directory
load_system_services() {
    if [ "${FORCE_LOAD_SYSTEM_SERVICES}" != "1" ]; then
        # return if system services already loaded
        test -e ${QORUS_INIT_STATE_DIR}/system_services_loaded && return
    fi

    echo "Loading system services"
    oload -lR ${OMQ_DIR}/system/*.q*
    touch ${QORUS_INIT_STATE_DIR}/system_services_loaded
}

####################
####################

do_init_steps() {
    # setup time zone in container
    setup_tz

    # configure qorus user and group env vars next
    configure_uid_gid_vars

    # write qorus UID and GID to files, so that we can set them correctly later when launching qorus
    write_qorus_uid_gid_files

    # add qorus user and group
    add_qorus_user_group

    # make sure that there's something in OMQ_DIR/etc directory
    fill_etc_dir

    # prepare Qorus for HTTPS
    prepare_https

    # chown of qorus dir only
    chown qorus:qorus $OMQ_DIR

    # configure database connection
    db_config

    # prepare DB schema
    prepare_schema

    # load system jobs, services etc.
    load_system_services

    # load the omquser datasource
    check_load_omquser

    # again make sure qorus dirs are owned by qorus user and group
    chown_qorus_dirs

    # signal that the init has finished
    touch ${QORUS_INIT_STATE_DIR}/init_finished
}

do_init_steps

echo "============================"
echo " Qorus Docker init complete"
echo "============================"; echo
