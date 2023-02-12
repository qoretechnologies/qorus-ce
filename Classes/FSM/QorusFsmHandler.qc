# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

#! Main namespace for handling of finite state machines
public namespace Fsm {
/**
    This class is an interface for finite state machines.
    It provides an API to retrieve/save state data and also an API to execute an FSM
 */
public class AbstractFsmHandler {
    /**
        Returns current state data for the given state of the given FSM
        @param fsm_name the name of the FSM
        @param execution_id the id of the FSM execution
        @param state_id the id of the state
        @return current data for the given state of the given FSM
    */
    abstract auto getStateData(string fsm_name, int execution_id, string state_id);

    /**
        Saves the given data for the given state of the given FSM
        @param fsm_name the name of the FSM
        @param execution_id the id of the FSM execution
        @param state_id the id of the state
        @param data_ the data to be set
    */
    abstract setStateData(string fsm_name, int execution_id, string state_id, auto data_);

    /**
        Clears all state data for the given state of the given FSM
        @param fsm_name the name of the FSM
        @param execution_id the id of the FSM execution
    */
    abstract clearStateData(string fsm_name, int execution_id);

    /**
        This method executes one instance of the given FSM

        @param fsm_name the name of the FSM
        @param input_data optional input data

        @return the result of executing the FSM, if any
    */
    abstract auto executeFsm(string fsm_name, auto input_data);

    /**
        @return current interface program object
    */
    abstract Program getInterfaceProgram();
}

/**
    This class provides finite state machines for Qorus interfaces (services, jobs and steps)
 */
public class QorusFsmHandler inherits AbstractFsmHandler {
    private:internal {
        Mutex stateDataMutex();
        hash<auto> stateData = {};

        # interface program object
        Program interfaceProgram;
    }

    private {
        # a map of all FSM instances that can be run
        hash<string, Fsm> fsmMap;
    }

    /**
        Creates a QorusFsmHandler from the user context

        @throw FSM-CONTEXT-ERROR in case it's called outside of a service, job or step
        @throw FSM-ERROR error in FSM definition
     */
    constructor() {
        ensure_create_tld();

        *hash<auto> context_info = UserApi::getUserContextInfo();
        if (!context_info) {
            throw "FSM-CONTEXT-ERROR", "QorusFsmHandler cannot be created outside of a service, job or step";
        }
        QDBG_LOG("QorusFsmHandler::constructor: context_info: %y", context_info);

        *hash<auto> interface = Qorus.qmm.lookupInterface(context_info.type, context_info.id);
        if (!interface) {
            throw "FSM-CONTEXT-ERROR", sprintf("unable to find an interface from the context: %N", context_info);
        }

        init(interface);
    }

    /**
        Creates a QorusFsmHandler from the user context

        @throw FSM-ERROR error in FSM definition
     */
    constructor(hash<auto> interface) {
        init(interface);
    }

    #! Common constructo code to set up FSM execution
    private:internal init(hash<auto> interface) {
        QDBG_LOG("QorusFsmHandler::constructor(): interface: %y", interface);

        interfaceProgram = _priv_get_pgm_ctx();

        UserApi::logDebug("QorusFsmHandler::constructor() interface fsm: %y", interface.lib.fsm);
        cacheFsm(interface.lib.fsm);
    }

    private:internal cacheFsm(*list<auto> fsm_lib) {
        QDBG_LOG("QorusFsmHandler::cacheFsm() fsm_lib: %y", fsm_lib);
        foreach hash<auto> fsm_info in (fsm_lib) {
            if (fsmMap.hasKey(fsm_info.name)) {
                continue;
            }

            *hash<auto> fsm_definition = Qorus.qmm.lookupFsm(fsm_info.name);
            QDBG_LOG("QorusFsmHandler::cacheFsm() fsm_definition: %y", fsm_definition);
            if (!fsm_definition) {
                throw "FSM-ERROR", sprintf("unable to find FSM %y", fsm_info.name);
            }
            Fsm fsm(fsm_info.name, fsm_definition, self);
            fsmMap{fsm_info.name} = fsm;
            FsmInfo info = fsm.getInfo();

            # cache all FSM libs
            cacheFsm(fsm_definition.lib.fsm);
        }
    }

    /**
        Implementation of the AbstractFsmHandler interface.
        @param fsm_name the name of the FSM
        @param input_data optional input data

        @return the result of executing the FSM, if any
    */
    auto executeFsm(string fsm_name, auto input_data) {
        if (!fsmMap.hasKey(fsm_name)) {
            throw "FSM-NOT-FOUND", sprintf("FSM with name %y cannot be found for the current context", fsm_name);
        }

        Fsm fsm = fsmMap{fsm_name};
        QDBG_LOG("QorusFsmHandler::executeFsm() executing FSM %y with args: %y", fsm_name, input_data);

        # ensure that each FSM has its own local data
        VarDataHelper vdh();

        FsmExecution fsm_exec = fsm.execute(input_data);
        return fsm_exec.getResult();
    }

    /**
        Implementation of the AbstractFsmHandler interface.
        @param fsm_name the name of the FSM
        @param execution_id the id of the FSM execution
        @param state_id the id of the state

        @return current data for the given state of the given FSM
    */
    auto getStateData(string fsm_name, int execution_id, string state_id) {
        stateDataMutex.lock();
        on_exit stateDataMutex.unlock();
        return stateData{fsm_name}{execution_id}{state_id};
    }

    /**
        @return the state data hash.
    */
    hash<auto> getStateData() {
        stateDataMutex.lock();
        on_exit stateDataMutex.unlock();
        return stateData;
    }

    /**
        Implementation of the AbstractFsmHandler interface.
        @param fsm_name the name of the FSM
        @param execution_id the id of the FSM execution
        @param state_id the id of the state
        @param data_ data_ to be set
    */
    setStateData(string fsm_name, int execution_id, string state_id, auto data_) {
        stateDataMutex.lock();
        on_exit stateDataMutex.unlock();
        stateData{fsm_name}{execution_id}{state_id} = data_;
    }

    /**
        Implementation of the AbstractFsmHandler interface.
        @param fsm_name the name of the FSM
        @param execution_id the id of the FSM execution
    */
    clearStateData(string fsm_name, int execution_id) {
        stateDataMutex.lock();
        on_exit stateDataMutex.unlock();
        remove stateData{fsm_name}{execution_id};
    }

    /**
        Implementation of the AbstractFsmHandler interface.
        @return current interface program object
    */
    Program getInterfaceProgram() {
        return interfaceProgram;
    }

    #! Registers the given FSM with the given object as an @ref DataProvider::Observer "Observer"
    /** @param fsm_name the name of the Finite State Machine to register with \a observable
        @param observable the event source object
        @param event_id the event ID to register with \a observable

        @throw FSM-NOT-FOUND The given Finite State Machine is not valid for the current interface context
    */
    registerFsmAsObserver(string fsm_name, DataProvider::Observable observable, string event_id) {
        *Fsm fsm = fsmMap{fsm_name};
        if (!fsm) {
            throw "FSM-NOT-FOUND", sprintf("FSM with name %y cannot be found for the current context", fsm_name);
        }

        observable.registerObserver(fsm, event_id);
    }

    #! Registers the given FSM with the given object as an @ref DataProvider::Observer "Observer"
    /** @param fsm_name the name of the Finite State Machine to register with \a observable
        @param observable the event source object
        @param event_id the event ID to register with \a observable

        @throw FSM-NOT-FOUND The given Finite State Machine is not valid for the current interface context

        @note this variant is meant for Java com.qoretechnologies.qorus.Observer objects; the Java classes declaration
        cannot be used here in the method signature due to the fact that Java classes in interface objects are loaded
        by another classloader
    */
    registerFsmAsObserver(string fsm_name, object observable, string event_id) {
        *Fsm fsm = fsmMap{fsm_name};
        if (!fsm) {
            throw "FSM-NOT-FOUND", sprintf("FSM with name %y cannot be found for the current context", fsm_name);
        }

        observable.registerObserver(fsm, event_id);
    }

    #! executes the given FSM and returns any output data
    /**
        @param fsm_name the Finite State Machine name to execute
        @param input_data and returns any output data any input data for the Finite State Machine

        @return the result of executing the FSM, if any

        @throw FSM-NOT-FOUND The given Finite State Machine is not valid for the current interface context
    */
    static auto executeFsm(string fsm_name, auto input_data) {
        QorusFsmHandler fsm_handler();
        auto rv = fsm_handler.executeFsm(fsm_name, input_data);
        QDBG_LOG("QorusFsmHandler::executeFsm() %y: rv: %N", fsm_name, rv);
        return rv;
    }

    #! Registers the given FSM with the given object as an @ref DataProvider::Observer "Observer"
    /** @param fsm_name the name of the Finite State Machine to register with \a observable
        @param observable the event source object
        @param event_id the event ID to register with \a observable

        @throw FSM-NOT-FOUND The given Finite State Machine is not valid for the current interface context
    */
    static registerFsmAsObserver(string fsm_name, DataProvider::Observable observable, string event_id) {
        QorusFsmHandler fsm_handler();
        fsm_handler.registerFsmAsObserver(fsm_name, observable, event_id);
    }

    #! Registers the given FSM with the given object as an @ref DataProvider::Observer "Observer"
    /** @param fsm_name the name of the Finite State Machine to register with \a observable
        @param observable the event source object
        @param event_id the event ID to register with \a observable

        @throw FSM-NOT-FOUND The given Finite State Machine is not valid for the current interface context

        @note this variant is meant for Java com.qoretechnologies.qorus.Observer objects; the Java classes declaration
        cannot be used here in the method signature due to the fact that Java classes in interface objects are loaded
        by another classloader
    */
    static registerFsmAsObserver(string fsm_name, object observable, string event_id) {
        QorusFsmHandler fsm_handler();
        fsm_handler.registerFsmAsObserver(fsm_name, observable, event_id);
    }
}
}
