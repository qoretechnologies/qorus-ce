#!/bin/sh

set -e
set -x

# check for final branches
if [ "${CI_COMMIT_BRANCH}" = "develop" -o "${CI_COMMIT_BRANCH}" = "5.1" ]; then
    echo 1
else
    echo 0
fi
