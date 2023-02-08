# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%require-types
%strict-args

#! This class performs common initialization for all programs that can hold interface container objects
class OMQ::QorusCommonInterface {
    public {
        int stack_set;

        #! global connection lock
        RWLock connection_rwl();

        const PostInitOptions = (
            "stack-size",
            "dataprovider-modules",
        );
    }

    #! Creates the object and performs common initialization
    constructor() {
        # register datasource and table lookups
        DbDataProvider::setDatasourceLookup(\UserApi::getDatasourcePool());
        DbDataProvider::setTableLookup(\UserApi::getSqlTable());
        # load known data provider factories
        DataProvider::registerKnownFactories();
        # load known data provider types
        DataProvider::registerKnownTypes();
        # register common Qorus data types
        registerQorusTypes();
    }

    #! Register common Qorus data types
    static registerQorusTypes() {
    }

    #! Perform common initialization once options are available
    /** @throws STACK-SIZE-ERROR if the qorus.stack-size option cannot be set
    */
    postInit(hash<auto> qorus_options, Logger logger) {
        # issue #3548: set stack size on demand
        *int stack_size = getStackSize(qorus_options);
        if (stack_size) {
            setStackSize(stack_size, logger);
        }

        foreach string mod in (qorus_options."dataprovider-modules") {
            try {
                load_module(mod);
            } catch (hash<ExceptionInfo> ex) {
                logger.log(LoggerLevel::ERROR, "failed to load dataprovider module %y: %s", mod, get_exception_string(ex));
            }
        }
        DataProvider::lockAllTypes();
    }

    #! Returns the custom stack size for the process; if any
    *int getStackSize(hash<auto> qorus_options) {
        return qorus_options."stack-size";
    }

    #! Set default thread stack size
    /** @throws STACK-SIZE-ERROR if the given stack size cannot be set
    */
    setStackSize(int stack_size, *Logger logger) {
        if (stack_set) {
            if (logger) {
                logger.log(LoggerLevel::INFO, "qorus.stack-size: set default stack size to %y", stack_set);
            }
            return;
        }
        int new_stack_size = set_default_thread_stack_size(stack_size);
        if (new_stack_size != stack_size) {
            throw "STACK-SIZE-ERROR", sprintf("cannot set stack size to %y; value after attempt: %y", stack_size,
                new_stack_size);
        }
        stack_set = stack_size;
        if (logger) {
            logger.log(LoggerLevel::INFO, "qorus.stack-size: set default stack size to %y", stack_size);
        }
    }
}
