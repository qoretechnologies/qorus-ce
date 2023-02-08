#!/bin/bash

set -x

do_tests() {
    if [ -f /tmp/env.sh ]; then
        . /tmp/env.sh
    elif [ -f /opt/qorus/bin/env.sh ]; then
        . /opt/qorus/bin/env.sh
    fi

    # turn on HTTP debugging
    qrest put system/listeners/qorus-1/setLogOptions option=-1 || true

    set +e
    for test in ${QORUS_SRC_DIR}/test/*.qtest; do
        # skip blacklisted tests
        bn=`basename $test|sed s/\.qtest$//`
        if [[ -n "$TEST_BLACKLIST" ]] && echo "$bn" | grep -qE "$TEST_BLACKLIST"; then
    	    continue
        fi

        # skip offline tests
        if [[ -n "$TEST_OFFLINE2" ]] && echo "$bn" | grep -qE "$TEST_OFFLINE2"; then
    	    continue
        fi

        # skip local tests if applicable
        if [ "${QORUS_SKIP_LOCAL_TESTS}" = "1" -a -n "`grep %include $test`" ]; then
            continue
        fi

        # run test and save the result
        date
        qore $test -vv
        RESULTS="$RESULTS $?"
        date
    done

    # run python tests
    for test in ${QORUS_SRC_DIR}/test/*.qtest.py; do
        # run test and save the result
        date
        python3 $test -vv
        RESULTS="$RESULTS $?"
        date
    done

    # make sure there were no asserts
    if [ -d ${QORUS_SRC_DIR}/log ]; then
        if grep ASSERT ${QORUS_SRC_DIR}/log/*log; then
            echo ASSERTs found, CI failed
            false
        else
            echo no ASSERTs found, CI OK
        fi
    fi

    # check the results
    for R in $RESULTS; do
        if [ "$R" != "0" ]; then
            exit 1 # fail
        fi
    done
}

if [ "${SKIP_QORUS_TESTS}" = "yes" ]; then
    echo skipping tests
else
    do_tests
fi
