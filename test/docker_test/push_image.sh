#!/bin/sh

set -x
set -e

# get CPU architecture
arch=`uname -m`

process_image() {
    # copy production image to storage area
    if [ -n "$2" ]; then
        tag=qorus-test-`echo $CI_COMMIT_BRANCH-$CI_PIPELINE_ID | sed 's,/,-,g'`-$2
    else
        tag=qorus-test-`echo $CI_COMMIT_BRANCH-$CI_PIPELINE_ID | sed 's,/,-,g'`
    fi
    source_name=$tag-$1.tar

    if [ -n "${SFTPSTORAGE_PKEY}" -a -n "${SFTPSTORAGE_HOST}" -a -n "${SFTPSTORAGE_HOSTKEY}" ]; then
        if [ ! -d ~/.ssh ]; then mkdir -m 0700 -p ~/.ssh; fi
        echo "${SFTPSTORAGE_HOSTKEY}" >> ~/.ssh/known_hosts
        export KEYFILE=/tmp/sftpstorage-ssh-key
        echo "${SFTPSTORAGE_PKEY}" > ${KEYFILE}
        chmod 600 ${KEYFILE}
        scp -i ${KEYFILE} ${SFTPSTORAGE_USER:-sftpstorage}@${SFTPSTORAGE_HOST}:qorus-test-images/$source_name $source_name
    else
        aws s3 cp s3://qorus-test-images/$source_name $source_name
    fi
    ls -l qorus-test*
    # load local image into local docker
    docker load -i $source_name
    # delete local image file after loading
    rm $source_name
    # set source and target tag env vars
    export SOURCE_IMAGE_TAG=$tag-$1
    if [ -n "$2" ]; then
        if [ "$1" = "aarch64" ]; then
            export TARGET_IMAGE_TAG=$CI_REGISTRY/qorus/qorus-ce/$IMAGE_NAME-$2-arm64
        else
            export TARGET_IMAGE_TAG=$CI_REGISTRY/qorus/qorus-ce/$IMAGE_NAME-$2-amd64
        fi
    else
        if [ "$1" = "aarch64" ]; then
            export TARGET_IMAGE_TAG=$CI_REGISTRY/qorus/qorus-ce/$IMAGE_NAME-arm64
        else
            export TARGET_IMAGE_TAG=$CI_REGISTRY/qorus/qorus-ce/$IMAGE_NAME-amd64
        fi
    fi
    # tag as target
    docker tag ${SOURCE_IMAGE_TAG} ${TARGET_IMAGE_TAG}
    # push to target repo
    docker push ${TARGET_IMAGE_TAG}
}

delete_image() {
    # delete production image from storage area
    if [ -n "$2" ]; then
        tag=qorus-test-`echo $CI_COMMIT_BRANCH-$CI_PIPELINE_ID | sed 's,/,-,g'`-$2
    else
        tag=qorus-test-`echo $CI_COMMIT_BRANCH-$CI_PIPELINE_ID | sed 's,/,-,g'`
    fi
    source_name=$tag-$1.tar
    if [ -n "${SFTPSTORAGE_PKEY}" -a -n "${SFTPSTORAGE_HOST}" ]; then
        # delete image from local SFTP storage
        ssh -i ${KEYFILE:-/tmp/sftpstorage-ssh-key} ${SFTPSTORAGE_USER:-sftpstorage}@${SFTPSTORAGE_HOST} rm qorus-test-images/$source_name
    else
        # delete image from s3
        aws s3 rm s3://qorus-test-images/$source_name
    fi
}

if [ "$MANUAL_IMAGE" != "1" ]; then
    if [ "$USE_LOCAL_AWS" != "1" ]; then
        # setup AWS access
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
    fi

    # login to target repo
    docker login -u gitlab-ci-token -p $CI_JOB_TOKEN $CI_REGISTRY

    # process amd64 image
    process_image x86_64
    # process arm64 image
    process_image aarch64

    # combine them into one image
    export TARGET_IMAGE_TAG=$CI_REGISTRY/qorus/qorus-ce/$IMAGE_NAME
    # create manifest from both images
    docker manifest create ${TARGET_IMAGE_TAG} --amend ${TARGET_IMAGE_TAG}-amd64 --amend ${TARGET_IMAGE_TAG}-arm64
    # push multiarch image to registry
    docker manifest push ${TARGET_IMAGE_TAG}

    # process amd64 go image
    process_image x86_64 go
    # process arm64 go image
    process_image aarch64 go

    # combine them into one image
    export TARGET_IMAGE_TAG=$CI_REGISTRY/qorus/qorus-ce/$IMAGE_NAME
    export TARGET_IMAGE_TAG_GO=`echo ${TARGET_IMAGE_TAG} | sed 's/:/-go:/'`
    # create manifest from both images
    docker manifest create ${TARGET_IMAGE_TAG_GO} --amend ${TARGET_IMAGE_TAG}-go-amd64 --amend ${TARGET_IMAGE_TAG}-go-arm64
    # push multiarch image to registry
    docker manifest push ${TARGET_IMAGE_TAG_GO}

    # delete all intermediate images at the end to ensure that the job can be restarted if necessary

    # delete amd64 image
    delete_image x86_64
    # delete arm64 image
    delete_image aarch64
    # delete amd64 go image
    delete_image go-x86_64
    # delete arm64 go image
    delete_image go-aarch64
else
    echo skipping image push; MANUAL_IMAGE=1
fi