# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

/*
The format:
    INVARIANT: reference_to_function,
    TRANSITIONS: {
                    condition: to_state,
                }
    IS_FINAL: True

Invariant function does not take any parameter and returns nothing.
*/
hashdecl StateInfo {
    bool is_final = False;
    *code invariant;
    hash<string, string> transitions();
}

/** FSA: Finite state automation.
    To create new FSA you should inherit from this class.
    Example:
        class MyFSA inherits FSA {
            private {
                hash<auto> transitions = {
                    "idle": <StateInfo>{
                        INVARIANT: \self.idle(),
                        TRANSITIONS: {
                            "do": "done"
                        }
                    },
                    "done": <StateInfo>{
                        IS_FINAL: True
                    }
                };
            }

            constructor() : FSA(transitions, "idle") {}

            idle() {}
        }

        # Then to use the class:
        MyFSA fsa();
        fsa.execute("do");

        # Finite state automation graph for this class:

                  do
        -> (idle) -> ((done))

    It's a Qorus private class - not exposed to public API.
*/
class FSA {
    private:internal {
        /* Should be in this format:
            {
                state_name: <StateInfo>{
                    INVARIANT: reference_to_function,
                    TRANSITIONS: {
                        condition: to_state,
                    }
                }
            }
        */
        hash<string, hash<StateInfo>> transitions;
        Mutex transitionMutex();
        string currentStateName;
        bool initialized;
    }

    public {
        const TRANSITIONS = "transitions";
        const INVARIANT = "invariant";
        const IS_FINAL = "is_final";
    }

    #! Constructs an empty FSA, initialize method must be called to initialize the FSA
    constructor() {
        initialized = False;
    }

    #! Initializes FSA object with given transitions and start state"
    /** @param transitions hash described above
        @param start_state start state
        @throw FSA-ERROR exception if the given start_state doesn't exist
        */
    synchronized initialize(hash<string, hash<StateInfo>> transitions_, string start_state) {
        if (initialized) {
            throw "FSA-ERROR", sprintf("FSA has been already initialized");
        }

        transitions = transitions_;
        changeStateTo(start_state);

        initialized = True;

        # call invariant if exists for start state
        if (exists transitions{currentStateName}{INVARIANT}) {
            transitions{currentStateName}{INVARIANT}();
        }
    }

    #! Changes current state to the given new_state
    /** @param new_state state to change to
        @throw FSA-ERROR exception if the given new_state doesn't exist
        */
    private changeStateTo(string new_state) {
        qlog(LoggerLevel::DEBUG, "Changing current state: %s, to state: %s", currentStateName, new_state);
        currentStateName = new_state;

        if (!exists transitions{currentStateName}) {
            throw "FSA-ERROR", sprintf("%s state does not exist, available states: %n",
                                       currentStateName,
                                       transitions.keys());
        }
    }

    private checkIfInitialized() {
        if (!initialized) {
            throw "FSA-ERROR",
                  sprintf("FSA was not initialized, please make sure initialize() method has been called");
        }
    }

    #! Executes transition if it exists for the current state
    /** @param transition transtion name to execute
        @return True if current state was changed, False if not
        @throw FSA-ERROR in case FSA was not initialized or the target state doesn't exist
    */
    bool execute(string transition) {
        checkIfInitialized();

        qlog(LoggerLevel::DEBUG, "Execute: %s from current state: %s", transition, currentStateName);

        {
            AutoLock auto_lock(transitionMutex);

            hash<StateInfo> current_state = transitions{currentStateName};
            hash<string, string> current_state_transitions = current_state{TRANSITIONS};

            if (!current_state_transitions{transition}) {
                qlog(LoggerLevel::DEBUG, "Current state: %s does not have transition: %s. It could be a final state.",
                     currentStateName,
                     transition);

                return False;
            }

            changeStateTo(current_state_transitions{transition});
        }

        if (exists transitions{currentStateName}{INVARIANT}) {
            qlog(LoggerLevel::DEBUG, "Running invariant for state %s", currentStateName);
            transitions{currentStateName}{INVARIANT}();
        }
        return True;
    }

    #! Checks if the current state is final
    /** @return True if current state is final, False if not
        @throw FSA-ERROR in case FSA was not initialized
        */
    bool isInFinalState() {
        checkIfInitialized();
        return transitions{currentStateName}.is_final;
    }
}
