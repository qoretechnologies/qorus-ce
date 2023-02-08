#!/bin/sh

set -e

get_external_apps() {
    ENV_FILE=/tmp/env.sh
    . ${ENV_FILE}

    # prepare OMQ_DIR
    mkdir -p ${OMQ_DIR}

    export WORKDIR=`pwd`

    if [ -n "${SFTPSTORAGE_PKEY}" -a -n "${SFTPSTORAGE_HOST}" -a -n "${SFTPSTORAGE_HOSTKEY}" ]; then
        if [ ! -d ~/.ssh ]; then mkdir -m 0700 -p ~/.ssh; fi
        echo "${SFTPSTORAGE_HOSTKEY}" >> ~/.ssh/known_hosts
        export KEYFILE=/tmp/sftpstorage-ssh-key
        echo "${SFTPSTORAGE_PKEY}" > ${KEYFILE}
        chmod 600 ${KEYFILE}
        echo "Downloading Prometheus build from ${SFTPSTORAGE_HOST}..."
        scp -i ${KEYFILE} ${SFTPSTORAGE_USER:-sftpstorage}@${SFTPSTORAGE_HOST}:qt-appbuilds/prometheus-build.tar.gz .
        echo "Downloading Grafana build from ${SFTPSTORAGE_HOST}..."
        scp -i ${KEYFILE} ${SFTPSTORAGE_USER:-sftpstorage}@${SFTPSTORAGE_HOST}:qt-appbuilds/grafana-build.tar.gz .
    else
        echo "Installing the AWS CLI..."
        if [ -n "`grep ID=alpine /etc/os-release`" ]; then
            # install the AWS CLI on Alpine
            apk add --no-cache python3 py3-pip
            pip3 install --upgrade pip
            pip3 install awscli
            rm -rf /var/cache/apk/*
        else
            # install the AWS CLI on standard linux
            mkdir /tmp/aws
            cd /tmp/aws

            # get CPU architecture
            arch=`uname -m`
            if [ "$arch" = "aarch64" ]; then
                curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
            else
                curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            fi

            unzip awscliv2.zip >/dev/null
            ./aws/install
            rm -rf aws
            cd -
        fi

        # download builds
        echo "Downloading Prometheus build from AWS S3..."
        aws s3 cp s3://qt-appbuilds/prometheus-build.tar.gz .
        echo "Downloading Grafana build from AWS S3..."
        aws s3 cp s3://qt-appbuilds/grafana-build.tar.gz .
    fi

    set -x

    # extract the builds
    tar xzf prometheus-build.tar.gz
    tar xzf grafana-build.tar.gz

    # move Grafana to OMQ_DIR
    cd ${WORKDIR}/external_apps/grafana/omqdir
    cp -rf ./* ${OMQ_DIR}/

    # move Prometheus to OMQ_DIR
    cd ${WORKDIR}/external_apps/prometheus/omqdir
    cp -rf ./* ${OMQ_DIR}/

    # delete sources
    cd ${WORKDIR}
    rm -rf exernal_apps
}

if [ "${SKIP_QORUS_TESTS}" = "yes" ]; then
    echo skipping getting external apps
else
    get_external_apps
fi
