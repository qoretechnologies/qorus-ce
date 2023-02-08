# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

#! main Qorus namespace
public namespace OMQ {
%ifndef NO_ORACLE
/** \brief An Oracle specific class which is used for automated instrumentation
    as in OracleExtensions::OracleDatasourcePool but this one is directly
    inherited from Qore::SQL::DatasourcePool.

    All user code gets this class automatically instead of raw DatasourcePool
    if is the datasource of Oracle type and the @ref oracle-datasource-pool
    option is set to \c True.

    The user code works as with standard OMQ::SQL::DatasourcePool out of the box.
    No changes in current code base are required.

    The auto instrumentation is provided by Qorus internal
    @ref OMQ::QorusOracleDatasourcePool::getOracleInstrumentation() method.

    User code can use all functionality of OracleExtensions::OracleInstrumentationBase
    like a custom application info etc.

    User code has to wrap OMQ::QorusOracleDatasourcePool into OracleExtensions::OracleDatasourcePool
    to use advanced extensions like "longops" or "server output".
 */
public class QorusOracleDatasourcePool inherits Qore::SQL::DatasourcePool, OracleExtensions::OracleInstrumentationBase {
    #! creates the object
    constructor(hash<auto> opts, *Qore::Thread::Queue queue, auto arg, code userAutoInfo) : Qore::SQL::DatasourcePool(opts, queue, arg), OracleExtensions::OracleInstrumentationBase(userAutoInfo) {
    }

    /** \brief A helper function for automated Oracle instrumentation in QorusOracleDatasourcePool.
    It tries to get the most valuable info form the current Qorus context
    to identify the place of the origin of the DB operation in the system
    or user code.

    Please see Qore OracleExtensions module and Oracle documentation for
    more information about Oracle instrumentation.

    <b>workflow:</b>
     - client_info: object type:name:version
     - module: name of the step function:version
     - action: wfiid:stepid:index

    <b>service:</b>
     - client_info: object type:service name:version
     - module:
     - action:

    <b>job:</b>
     - client_info: jobname:version
     - module:
     - action: job_instanceid

    <b>Example</b>
    @code{.py}
# type: STEP
# version: 1.0
# desc: a test step
# author: Petr Vanek (Qore Technologies, sro)
%new-style

sub rem_stream_send() {
    DatasourcePool dsstage = UserApi::getDatasourcePool("omquser");
    on_success dsstage.commit();
    on_error dsstage.rollback();

    log(LoggerLevel::INFO, "DS: %y", dsstage);
    # wait 5s in the DB
    dsstage.exec("begin dbms_lock.sleep(5); end;");
    # ... code skip ...
}
# END
    @endcode

    Log output for dsstage will be:
    @code{.py}
DS: {<QorusOracleDatasourcePool object>: userInfo: null, autoCode: function reference (0x7fa3e0fefeb0), m_ds: null}
    @endcode

    Oracle's \c V$SESSION will contain these values for current connection:
     - module: @code{.py} rem_stream_send:1.0 @endcode
     - action: @code{.py} 200:316:0 @endcode
     - client_info: @code{.py} workflow:REMOTE-STREAM-TEST:1.0 @endcode
     */
    static *OracleExtensions::OracleApplicationInfo getOracleInstrumentation() {
        # issue #2168: support oracle context auditing
        string client;
        string module; # TODO/FIXME: what to use in jobs/services?
        softstring action;

        if (*hash cx = get_thread_data("dsp_thread_ctx")) {
            client = sprintf("%s:%s:%s", cx.type, cx.name, cx.version);

            if (cx.job_instanceid)
                action = cx.job_instanceid;
            else if (cx.stepid) {
                action = sprintf("%s:%s:%s", cx.workflow_instanceid, cx.stepid, cx.ind);
                module = sprintf("%s:%s", cx.stepname, cx.stepversion);
            }
            #Qorus.log(LoggerLevel::DEBUG, "DEBUG: client: %y action: %y module: %y", client, action, module);
            # TODO/FIXME: service method?
        } else {
            client = "qorus";
            module = "system";
        }

        if (!action.val())
            action = "n/a";

        return new OracleExtensions::OracleApplicationInfo(client, module, action);
    }

    nothing setAppInfoCallback(*string oraclient, *string oramodule, *string oraaction) {
        DatasourcePool::exec("begin
                dbms_application_info.set_client_info(%v);
                dbms_application_info.set_module(%v, %v);
            end;", oraclient, oramodule, oraaction);
    }

    bool currentThreadInTransaction() {
        return DatasourcePool::currentThreadInTransaction();
    }

    #! Start new transaction with potential automatic Aplication info set
    nothing beginTransaction() {
        DatasourcePool::beginTransaction();
        setAutomaticDBInfo(NOTHING, False);
    }

    #! Commit the transaction. Application info is cleared.
    nothing commit() {
        # required to clear info
        setAppInfo(NOTHING, False);
        DatasourcePool::commit();
    }

    #! Rollback the transaction. Application info is cleared.
    nothing rollback() {
        # required to clear info
        setAppInfo(NOTHING, False);
        DatasourcePool::rollback();
    }

    #! exec with automatic approach of getting application info
    /**
        @param sql a SQL statement
        @param ... binding arguments as in parent class method

        @retval any a result as in parent class method

    This method tries to find application info automatically. The previously set
    info (beginTransaction, setAppInfo) is used or a context related info
    is used in Qorus Integration Engine.
     */
    auto exec(string sql) {
        bool doRollback = setAutomaticDBInfo();
        on_error {
            if (doRollback)
                rollback();
        }
        #setAutomaticDBInfo(NOTHING, False);
        return DatasourcePool::vexec(sql, argv);
    }

    #! execRaw with automatic approach of getting application info
    /**
        @param sql a SQL statement
        @retval any a result as in parent class method

    This method tries to find application infautomatically. The previously set
    info (beginTransaction, setAppInfo) is used or a context related info
    is used in Qorus Integration Engine.
     */
    auto execRaw(string sql) {
        bool doRollback = setAutomaticDBInfo();
        on_error {
            if (doRollback)
                rollback();
        }
        #setAutomaticDBInfo(NOTHING, False);
        return DatasourcePool::execRaw(sql);
    }

    #! select with automatic approach of getting application info
    /**
        @param sql a SQL statement
        @param ... binding arguments as in parent class method
        @retval any a result as in parent class method

    This method tries to find application info automatically. The previously set
    info (beginTransaction, setAppInfo) is used or a context related info
    is used in Qorus Integration Engine.
     */
    auto select(string sql) {
        bool doRollback = setAutomaticDBInfo();
        on_exit {
            if (doRollback)
                rollback();
        }
        return DatasourcePool::vselect(sql, argv);
    }

    #! selectRow with automatic approach of getting application info
    /**
        @param sql a SQL statement
        @param ... binding arguments as in parent class method
        @retval any a result as in parent class method

    This method tries to find application info automatically. The previously set
    info (beginTransaction, setAppInfo) is used or a context related info
    is used in Qorus Integration Engine.
     */
    auto selectRow(string sql) {
        bool doRollback = setAutomaticDBInfo();
        on_exit {
            if (doRollback)
                rollback();
        }
        return DatasourcePool::vselectRow(sql, argv);
    }

    #! selectRows with automatic approach of getting application info
    /**
        @param sql a SQL statement
        @param ... binding arguments as in parent class method
        @retval any a result as in parent class method

    This method tries to find application info automatically. The previously set
    info (beginTransaction, setAppInfo) is used or a context related info
    is used in Qorus Integration Engine.
     */
    auto selectRows(string sql) {
        bool doRollback = setAutomaticDBInfo();
        on_exit {
            if (doRollback)
                rollback();
        }
        return DatasourcePool::vselectRows(sql, argv);
    }

    #! vexec with automatic approach of getting application info
    /**
        @param sql a SQL statement
        @param vargs binding arguments as in parent class method
        @retval any a result as in parent class method

    This method tries to find application info automatically. The previously set
    info (beginTransaction, setAppInfo) is used or a context related info
    is used in Qorus Integration Engine.
     */
    auto vexec(string sql, softlist<auto> vargs) {
        bool doRollback = setAutomaticDBInfo();
        on_error {
            if (doRollback)
                rollback();
        }
        #setAutomaticDBInfo(NOTHING, False);
        return DatasourcePool::vexec(sql, vargs);
    }

    #! vselect with automatic approach of getting application info
    /**
        @param sql a SQL statement
        @param vargs binding arguments as in parent class method
        @retval any a result as in parent class method

    This method tries to find application info automatically. The previously set
    info (beginTransaction, setAppInfo) is used or a context related info
    is used in Qorus Integration Engine.
     */
    auto vselect(string sql, softlist<auto> vargs) {
        bool doRollback = setAutomaticDBInfo();
        on_exit {
            if (doRollback)
                rollback();
        }
        return DatasourcePool::vselect(sql, vargs);
    }

    #! vselectRow with automatic approach of getting application info
    /**
        @param sql a SQL statement
        @param vargs binding arguments as in parent class method
        @retval any a result as in parent class method

    This method tries to find application info automatically. The previously set
    info (beginTransaction, setAppInfo) is used or a context related info
    is used in Qorus Integration Engine.
     */
    auto vselectRow(string sql, softlist<auto> vargs) {
        bool doRollback = setAutomaticDBInfo();
        on_exit {
            if (doRollback)
                rollback();
        }
        return DatasourcePool::vselectRow(sql, vargs);
    }

    #! vselectRows with automatic approach of getting application info
    /**
        @param sql a SQL statement
        @param vargs binding arguments as in parent class method
        @retval any a result as in parent class method

    This method tries to find application info automatically. The previously set
    info (beginTransaction, setAppInfo) is used or a context related info
    is used in Qorus Integration Engine.
     */
    auto vselectRows(string sql, softlist<auto> vargs) {
        bool doRollback = setAutomaticDBInfo();
        on_exit {
            if (doRollback)
                rollback();
        }
        return DatasourcePool::vselectRows(sql, vargs);
    }
}
%endif
}
