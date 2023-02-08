#!/bin/bash
set -e

. /tmp/env.sh

export QORUS_ALLOW_ROOT=1

launch_tests() {
    ${QORUS_SRC_DIR}/test/docker_test/init.sh
    gosu qorus:qorus ${QORUS_SRC_DIR}/test/docker_test/launch_qorus.sh
    gosu qorus:qorus ${QORUS_SRC_DIR}/test/docker_test/run_tests.sh
    gosu qorus:qorus ${QORUS_SRC_DIR}/test/docker_test/run_plugin_tests.sh
    gosu qorus:qorus ${QORUS_SRC_DIR}/test/docker_test/turn_off_qorus.sh
    gosu qorus:qorus ${QORUS_SRC_DIR}/test/docker_test/run_offline_tests.sh
}

launch() {
    if [ "${SKIP_QORUS_TESTS}" = "yes" ]; then
        echo skipping Qorus tests
    else
        launch_tests
    fi
}

case "$1" in
    "bash")
        exec "$@"
    ;;
    "sh")
        exec "$@"
    ;;
    "")
        launch
    ;;
    *)
        launch
    ;;
esac

# drop oracle user if necessary
if [ -n "${ORACLE_USER}" ]; then
    export ORACLE_USER
    qore -ne '
string username = ENV.ORACLE_USER.upr();
Datasource ds("oracle:system/qore@rippy");
while (True) {
    try {
        printf("dropping user %y...\n", username);
        ds.exec("drop user %s cascade", username);
        ds.commit();
        printf("done\n");
    } catch (hash<ExceptionInfo> ex) {
        if (ex.arg.alterr == "OCI-01940") {
            # get list of SID and SERIAL# values to kill all open sessions for this user
            printf("%s: %s; killing all open sessions for user %y\n", ex.err, ex.desc, username);
            *list<hash<auto>> l = ds.selectRows("select s.sid, s.serial# as serial from v$session s, "
                "v$process p where s.username = %v and p.addr(+) = s.paddr", username);
            foreach hash<auto> h in (l) {
                on_error ds.rollback();
                on_success ds.commit();
                string sql = sprintf("alter system kill session '"'"'%d,%d'"'"'", h.sid, h.serial);
                printf("sql: %s\n", sql);
                ds.exec(sql);
                printf("killed sid %d, serial %d for user %y\n", h.sid, h.serial, username);
            }
            printf("done, retrying drop user %y\n", username);
            continue;
        }
        rethrow;
    }
    break;
}'
    echo dropped oracle user ${ORACLE_USER}
elif [ "${POSTGRES_RIPPY}" = "1" ]; then
    # drop postgresql user / database if applicable
    cleanup_postgres_on_rippy
fi
