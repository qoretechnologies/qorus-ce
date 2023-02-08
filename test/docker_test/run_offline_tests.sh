#!/bin/bash

set -x

. /tmp/env.sh

# run offline tests
RESULTS=""
set +e
if [ -n "$TEST_OFFLINE" ]; then
    for test in $TEST_OFFLINE; do
        if [ -e ${QORUS_SRC_DIR}/test/$test.qtest ]; then
            # skip blacklisted tests
            bn=`basename $test|sed s/\.qtest$//`
            if [[ -n "$TEST_BLACKLIST" ]] && echo "$bn" | egrep "$TEST_BLACKLIST" > /dev/null; then
                continue
            fi

            # run test and save the result
            date
            qore ${QORUS_SRC_DIR}/test/$test.qtest -vv
            RESULTS="$RESULTS $?"
            date
        fi
    done
fi

# check the results
for R in $RESULTS; do
    if [ "$R" != "0" ]; then
        exit 1 # fail
    fi
done