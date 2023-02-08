#!/bin/bash

#
# Minimal init script for "no-init" Qorus start.
#
# Qorus user and group need to be created for correct Qorus functioning.
#

set -e

. /opt/qorus/bin/env.sh

#############################
# Qorus user and group setup
#############################

# default values for pre-created qorus account
DEFAULT_QORUS_UID=1000
DEFAULT_QORUS_GID=1000

# setup time zone on server
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
        fi
    fi
}

# chown necessary dirs for Qorus to Qorus user and group
chown_qorus_dirs() {
    if [ ! -d ${OMQ_DIR}/releases ]; then
        mkdir ${OMQ_DIR}/releases
    fi
    qorus_dirs="etc log user releases"
    for qd in ${qorus_dirs}; do
        qd_uid=`ls $OMQ_DIR -n | grep "$qd\$" | xargs | cut -d' ' -f3`
        qd_gid=`ls $OMQ_DIR -n | grep "$qd\$" | xargs | cut -d' ' -f4`
        if [ "$qd_uid" != "$QORUS_UID" ] || [ "$qd_gid" != "$QORUS_GID" ]; then
            echo "Changing ownership of OMQ_DIR/${qd} to '${QORUS_UID}:${QORUS_GID}'"
            chown -R ${QORUS_UID}:${QORUS_GID} ${OMQ_DIR}/${qd}
        fi
    done
    echo "Changing ownership of OMQ_DIR to '${QORUS_UID}:${QORUS_GID}'"
    chown ${QORUS_UID}:${QORUS_GID} ${OMQ_DIR}
}

####################
####################

do_init_steps() {
    # setup time zone in container
    setup_tz

    # configure qorus user and group env vars first
    configure_uid_gid_vars

    # add qorus user and group if they don't exist
    add_qorus_user_group

    # make qorus dirs owned by qorus user and group
    chown_qorus_dirs
}

do_init_steps
