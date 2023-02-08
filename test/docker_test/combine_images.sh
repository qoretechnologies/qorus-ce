#!/bin/sh

set -x
set -e

if [ "$MANUAL_IMAGE" != "1" ]; then
    # login to target repo
    docker login -u gitlab-ci-token -p $CI_JOB_TOKEN $CI_REGISTRY

    # combine them into one image
    export TARGET_IMAGE_TAG=$CI_REGISTRY/qorus/qorus-ce/$IMAGE_NAME
    # create manifest from both images
    docker manifest create ${TARGET_IMAGE_TAG} --amend ${TARGET_IMAGE_TAG}-amd64 --amend ${TARGET_IMAGE_TAG}-arm64
    # push multiarch image to registry
    docker manifest push ${TARGET_IMAGE_TAG}
else
    echo skipping image push; MANUAL_IMAGE=1
fi
