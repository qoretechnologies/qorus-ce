. /tmp/env.sh
cp -r QorusObjectParser/ Qyaml/ ${INSTALL_PREFIX}/share/qore-modules/
for test in test/*.qtest; do
    qore $test -vv
    RESULTS="$RESULTS $?"
done

# check the results
for R in $RESULTS; do
    if [ "$R" != "0" ]; then
        exit 1 # fail
    fi
done

