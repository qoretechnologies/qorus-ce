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
    Helper class for storing FSM information
 */
public class FsmInfo {
    private {
        Fsm fsm;
        string name;
        hash<auto> fsmDefinition;

        # state name -> state info
        hash<string, hash<auto>> init_states = {};

        # class name -> Reflection::Class object
        hash<string, Reflection::Class> class_cache = {};

        # state name -> class name -> prefix (empty string is OK) -> True
        hash<auto> class_pfx_map = {};

        # class name -> connector name -> connector info
        hash<auto> class_connectors = {};

        # state name -> mapper name -> True
        hash<string, hash<string, bool>> mappers = {};

        # state name -> pipeline name -> QorusPipelineFactory
        hash<string, hash<string, QorusPipelineFactory>> pipelines = {};

        # state name -> pipeline name -> pipeline options
        hash<string, hash<string, hash<auto>>> pipeline_opts = {};

        # FSM blocks; id -> info
        hash<string, FsmInfo> block_map;

        #! API call map: state -> hash{provider, options}
        hash<string, hash<auto>> apicalls;

        #! search single map: state -> hash{provider, options}
        hash<string, hash<auto>> search_single_map;

        #! search map: state -> hash{provider, options}
        hash<string, hash<auto>> search_map;

        #! update map: state -> hash{provider, options}
        hash<string, hash<auto>> update_map;

        #! delete map: state -> hash{provider, options}
        hash<string, hash<auto>> delete_map;

        #! create map: state -> hash{provider, options}
        hash<string, hash<auto>> create_map;

        #! Input type, if any
        *AbstractDataProviderType input_type;

        #! Output type, if any
        *AbstractDataProviderType output_type;

        # FSMInfo parent
        *FsmInfo parent;

        const EVENT_CONNECTOR_TYPE = "event";
        const CONDITION_CONNECTOR_TYPE = "condition";
        const INPUT_CONNECTOR_TYPE = "input";
        const OUTPUT_CONNECTOR_TYPE = "output";
        const INPUT_OUTPUT_CONNECTOR_TYPE = "input-output";

        # allowed action connector types
        const ActionConnectorTypes = {
            INPUT_CONNECTOR_TYPE: True,
            OUTPUT_CONNECTOR_TYPE: True,
            INPUT_OUTPUT_CONNECTOR_TYPE: True,
        };
    }

    /**
        Constructs an FsmInfo object with the given FSM definition hash

        @param fsm reference to the FSM object
        @param name the name of the FSM
        @param fsm_definition the FSM info hash according to the YAML schema

        @throw FSM-INIT-ERROR in case cannot be initialized
     */
    constructor(Fsm fsm, string name, hash<auto> fsm_definition, *FsmInfo parent) {
        self.fsm = fsm;
        self.name = name;
        fsmDefinition = fsm_definition;
        processFsmDefinition();
        self.parent = parent;
    }

    /**
        @return name of the FSM
     */
    string getName() {
        return name;
    }

    /**
        @return FSM definition hash
     */
    hash<auto> getDefinition() {
        return fsmDefinition;
    }

    /**
        @param name the state name
        @return FSM state info as a hash
     */
    hash<auto> getStateInfo(string name) {
        *hash<auto> rv = fsmDefinition.states{name};
        if (!rv) {
            throw "FSM-ERROR", sprintf("FSM %y references unknown state %y; known state keys: %y", self.name, name,
                keys fsmDefinition.states);
        }
        return rv  + {
            "key": name,
        };
    }

    /**
        @return FSM initial states as a hash
     */
    hash<auto> getInitialStates() {
        return init_states;
    }

    /**
        @return FSM class prefix map as a hash
     */
    hash<auto> getClassPrefixMap() {
        return class_pfx_map;
    }

    #! Returns the input type, if any
    *AbstractDataProviderType getInputType() {
        return input_type;
    }

    #! Returns the output type, if any
    *AbstractDataProviderType getOutputType() {
        return output_type;
    }

    #! executes the given block and returns the result
    auto executeBlock(hash<auto> state_info, auto input_data, FsmStrategy strategy) {
        *FsmInfo block = block_map{state_info.id};
        if (!block) {
            throw "BLOCK-NOT-FOUND", sprintf("FSM %y has no block with ID %y (corresponding to state %y); valid "
                "blocks: %y", name, state_info.id, state_info.name, keys block_map);
        }

        # ensure that each FSM has its own local data
        VarDataHelper vdh();

        switch (block.fsmDefinition."block-type") {
            case "for":
                return executeForBlock(input_data, state_info, block, strategy);

            case "foreach":
                return executeForEachBlock(input_data, state_info, block, strategy);

            case "while":
                return executeWhileBlock(input_data, state_info, block, strategy);

            default:
                throw "INVALID-BLOCK-TYPE", sprintf("FSM %y state %y has unknown block type %y; expecting 'for', "
                    "'foreach', or 'while'", name, state_info.name, block.fsmDefinition."block-type");
        }
    }

    private auto executeForBlock(auto input_data, hash<auto> state_info, FsmInfo block, FsmStrategy strategy) {
        hash<auto> block_config = block.fsmDefinition."block-config";
        string lang = block_config.language ?? "qore";

        # evaluate init expression
        if (exists block_config.init && exists block_config.init_var) {
            string label = sprintf("%s:%s: for init expr", name, state_info.name);
            auto value = strategy.evaluateExpression(state_info, block_config.init, lang, label, input_data);
            QDBG_LOG("FSM %y block %y: for init: %y = %y", name, state_info.name, block_config.init_var, value);
            UserApi::updateOutputData("x", value, {"x": "$var:{" + block_config.init_var + "}"});
        }

        auto return_value;

        string cond_label;
        string update_label;
        while (True) {
            # evaluate condition expression, if any
            if (exists block_config.condition) {
                if (!cond_label) {
                    cond_label = sprintf("%s:%s: for condition expr", name, state_info.name);
                }
                bool value = strategy.evaluateExpression(state_info, block_config.condition, lang, cond_label,
                    input_data).toBool();
                QDBG_LOG("FSM %y block %y: for cond: %y = %y", name, state_info.name, block_config.condition, value);
                if (!value) {
                    break;
                }
            }

            try {
                return_value = doBlockExecution(input_data, state_info.name, block);
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "FSM-BREAK") {
                    UserApi::logInfo("FSM %y state %y exec ID %d break exception encountered; breaking for loop",
                        name, state_info.name, strategy.getExecId());
                    break;
                } else if (ex.err == "FSM-CONTINUE") {
                    UserApi::logInfo("FSM %y state %y exec ID %d continue exception encountered; continuing for loop",
                        name, state_info.name, strategy.getExecId());
                } else {
                    rethrow;
                }
            }

            # evaluate update expression, if any
            if (exists block_config.update && exists block_config.update_var) {
                if (!update_label) {
                    update_label = sprintf("%s:%s: for update expr", name, state_info.name);
                }
                auto value = strategy.evaluateExpression(state_info, block_config.update, lang, update_label,
                    input_data);
                QDBG_LOG("FSM %y block %y: for update: %y = %y", name, state_info.name, block_config.update_var, value);
                UserApi::updateOutputData("x", value, {"x": "$var:{" + block_config.update_var + "}"});
            }
        }
        return return_value;
    }

    private auto executeForEachBlock(auto input_data, hash<auto> state_info, FsmInfo block, FsmStrategy strategy) {
        # evaluate loop expression
        hash<auto> block_config = block.fsmDefinition."block-config";
        string lang = block_config.language ?? "qore";
        string label = sprintf("%s:%s: foreach expr", name, state_info.id);
        auto value = strategy.evaluateExpression(state_info, block_config.loop, lang, label, input_data);
        QDBG_LOG("FSM %y block %y: foreach loop: %y = %y", name, state_info.name, block_config.loop, value);
        auto return_value;
        foreach auto val in (value) {
            try {
                return_value = doBlockExecution(val, state_info.name, block);
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "FSM-BREAK") {
                    UserApi::logInfo("FSM %y state %y exec ID %d break exception encountered; breaking foreach loop",
                        name, state_info.name, strategy.getExecId());
                    break;
                } else if (ex.err == "FSM-CONTINUE") {
                    UserApi::logInfo("FSM %y state %y exec ID %d continue exception encountered; continuing foreach "
                        "loop", name, state_info.name, strategy.getExecId());
                } else {
                    rethrow;
                }
            }
        }
        return return_value;
    }

    private auto executeWhileBlock(auto input_data, hash<auto> state_info, FsmInfo block, FsmStrategy strategy) {
        auto return_value;

        hash<auto> block_config = block.fsmDefinition."block-config";
        string lang = block_config.language ?? "qore";
        string cond_label;
        while (True) {
            # evaluate condition expression, if any
            if (exists block_config.condition) {
                if (!cond_label) {
                    cond_label = sprintf("%s:%s: for condition expr", name, state_info.id);
                }
                bool value = strategy.evaluateExpression(state_info, block_config.condition, lang, cond_label,
                    input_data).toBool();
                QDBG_LOG("FSM %y block %y: while cond: %y = %y", name, state_info.name, block_config.condition, value);
                if (!value) {
                    break;
                }
            }

            try {
                return_value = doBlockExecution(input_data, state_info.name, block);
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "FSM-BREAK") {
                    UserApi::logInfo("FSM %y state %y exec ID %d break exception encountered; breaking while loop",
                        name, state_info.name, strategy.getExecId());
                    break;
                } else if (ex.err == "FSM-CONTINUE") {
                    UserApi::logInfo("FSM %y state %y exec ID %d continue exception encountered; continuing while "
                        "loop", name, state_info.name, strategy.getExecId());
                } else {
                    rethrow;
                }
            }
        }
        return return_value;
    }

    private auto doBlockExecution(auto input_data, string block_name, FsmInfo block) {
        auto result;
        if (block.fsmDefinition.fsm) {
            QDBG_LOG("executing FSM %y block %y (FSM %y)", name, block_name, block.fsmDefinition.fsm);
            result = fsm.getFsmHandler().executeFsm(block.fsmDefinition.fsm, input_data);
        } else {
            QDBG_LOG("executing FSM %y block %y (%d state(s))", name, block_name, block.fsmDefinition.states.size());
            result = fsm.executeBlock(input_data, block_name, block).getResult();
        }
        QDBG_LOG("FSM %y result: %N", block_name, result);
        return result;
    }

    /**
        Creates a new object for the given class name and prefix

        @param state the local name of the state
        @param class_name the class name
        @param prefix optional prefix of the class name

        @return class object

        @throw FSM-ERROR if the given class with prefix is not known for the given state
     */
    auto createClassObject(hash<auto> state_info, string class_name, *string prefix) {
        if (!class_pfx_map{state_info.key}{class_name}{prefix} || !class_cache.hasKey(class_name)) {
            throw "FSM-ERROR", sprintf("FSM %y state %y: unknown class %y%s", name, state_info.name, class_name,
                prefix ? sprintf(" (with prefix %y", prefix) : "");
        }
        return class_cache{class_name}.newObjectArgs(prefix);
    }

    /**
        @return FSM class connectors as a hash
     */
    hash<auto> getClassConnectors() {
        return class_connectors;
    }

    /**
        @param class_name the class name
        @param name the connector name
        @return FSM class connector as a hash
     */
    hash<auto> getClassConnector(string class_name, string name) {
        return class_connectors{class_name}{name};
    }

    /**
        @return FSM mappers as a hash
     */
    hash<auto> getMappers() {
        return mappers;
    }

    /**
        @param state the local name of the state
        @param name the name of the mapper
        @return mapper object for the given name
        @throw FSM-ERROR if the given mapper is not known for the given state
     */
    Mapper::Mapper getMapper(hash<auto> state_info, string name) {
        if (!mappers{state_info.key}{name}) {
            throw "FSM-ERROR", sprintf("FSM %y state %y refers to unknown mapper %y", self.name, state_info.name, name);
        }
        # always return a new object
        return get_specific_mapper(name);
    }

    /**
        @param state the local name of the state
        @param name the name of the pipeline
        @return QorusPipelineFactory object for the given name
     */
    QorusPipelineFactory getPipeline(string state, string name) {
        return pipelines{state}{name};
    }

    #! Return pipeline options, if any
    *hash<auto> getPipelineOptions(string state, string name) {
        return pipeline_opts{state}{name};
    }

    #! Return the data provider for the given API call state
    AbstractDataProvider getDataProviderForApiCallState(string state, reference<string> provider_path,
            reference<hash<auto>> request_options) {
        if (*hash<auto> opts = apicalls{state}.request_options) {
            request_options = opts;
        }
        return UserApi::getDataProvider(provider_path = apicalls{state}.provider);
    }

    #! Return the data provider for the given single-record search state
    AbstractDataProvider getDataProviderForSearchSingleState(string state, reference<string> provider_path) {
        return UserApi::getDataProvider(provider_path = search_single_map{state}.provider);
    }

    #! Return the data provider for the given record search state
    AbstractDataProvider getDataProviderForSearchState(string state, reference<string> provider_path) {
        return UserApi::getDataProvider(provider_path = search_map{state}.provider);
    }

    #! Return the data provider for the given record update state
    AbstractDataProvider getDataProviderForUpdateState(string state, reference<string> provider_path) {
        return UserApi::getDataProvider(provider_path = update_map{state}.provider);
    }

    #! Return the data provider for the given record delete state
    AbstractDataProvider getDataProviderForDeleteState(string state, reference<string> provider_path) {
        return UserApi::getDataProvider(provider_path = delete_map{state}.provider);
    }

    #! Return the data provider for the given record create state
    AbstractDataProvider getDataProviderForCreateState(string state, reference<string> provider_path) {
        return UserApi::getDataProvider(provider_path = create_map{state}.provider);
    }

    /**
        @param name the name of the option
        @return value of the given option
     */
    auto getOption(string name) {
        return fsmDefinition.options{name};
    }

    /**
        @return AbstractFsmHandler
     */
    AbstractFsmHandler getFsmHandler() {
        return fsm.getFsmHandler();
    }

    auto getStateData(string state, int exec_id) {
        return fsm.getFsmHandler().getStateData(name, exec_id, fsmDefinition.states{state}.id);
    }

    auto getConfigItemValue(string state, string cfg_item, *hash<auto> local_context, bool expand_complex_values) {
        #QDBG_LOG("getConfigItemValue() cfg_item: %y state: %y: %y", cfg_item, state, fsmDefinition.states{state});
        hash<auto> state_info = fsmDefinition.states{state};
        string full_name = state_info.id + ":" + cfg_item;
        *hash<auto> config = fsmDefinition.config{full_name} ?? parent.fsmDefinition.config{full_name};
        if (!config) {
            throw "CONFIG-ITEM-ERROR", sprintf("FSM %y state %y: config item %y is unknown; known config "
                "items: %y", name, state_info.name, full_name, keys (fsmDefinition.config ??
                parent.fsmDefinition.config));
        }

        return getConfigItemValueIntern(state_info, full_name, config, local_context, expand_complex_values);
    }

    hash<auto> getConfigItemHash(string state, *hash<auto> local_context) {
        # issue #3656: only
        hash<auto> state_info = fsmDefinition.states{state};
        string pfx_pat = "^" + state_info.id + ":";
        return (map {regex_extract($1.key, pfx_pat + "(.+)$")[0]: getConfigItemValueIntern(state_info, $1.key,
            $1.value, local_context)},
            fsmDefinition.config.pairIterator(),
            regex($1.key, pfx_pat)) ?? {};
    }

    private auto getConfigItemValueIntern(hash<auto> state_info, string full_name, hash<auto> config,
            *hash<auto> local_context, bool expand_complex_values = True) {
        *string level;
        bool is_set;
        auto value = Qorus.qmm.findConfigItemValue("fsm", name, full_name, config, \level, \is_set);
        if (!config.allowed_values) {
            value = UserApi::expandTemplatedValue(value, local_context, expand_complex_values);
        }
        if (is_set) {
            # TODO: check type
            return value;
        }
        throw "CONFIG-ITEM-ERROR", sprintf("FSM %y state %y: config item %y has neither a value nor a default value",
            name, state_info.name, full_name);
    }

    #! caches needed information from the FSM definition
    private processFsmDefinition() {
        # process types
        if (fsmDefinition.input_type) {
            input_type = _priv_get_type_from_hash(fsmDefinition.input_type, "base_type");
        }
        if (fsmDefinition.output_type) {
            output_type = _priv_get_type_from_hash(fsmDefinition.output_type, "type");
        }

        code cacheConnectorsInConditions = sub (string state, *list<auto> transitions) {
            foreach hash<auto> transition in (transitions) {
                if (transition.hasKey("condition") && transition.condition.typeCode() == NT_HASH) {
                    QDBG_ASSERT(transition.condition.hasKey("class"));
                    cacheClassConnectorForState(state, transition.condition, True);
                }
            }
        };

        # get sorted initial states
        {
            hash<string, hash<string, hash<auto>>> smap;
            foreach hash<auto> i in (fsmDefinition.states.pairIterator()) {
                if (!i.value.initial) {
                    continue;
                }
                softstring ix = i.value.execution_order ?? "zzzzzzzzzzzzzzzzzzzz";
                smap{ix}{i.key} = i.value;
            }
            if (smap) {
                map init_states += smap{$1}, sort(keys smap);
            }
        }

        foreach hash<auto> state_iterator in (fsmDefinition.states.pairIterator()) {
            if (state_iterator.value.type == "block") {
                block_map{state_iterator.value.id} = new FsmInfo(fsm, name, state_iterator.value, parent ?? self);
                continue;
            } else if (state_iterator.value.type == "if") {
                # make quick references to true and false transitions
                map fsmDefinition.states{state_iterator.key}.if_transition{$1.branch} = $1,
                    state_iterator.value.transitions;
            }

            if (state_iterator.value.hasKey("action")) {
                switch (state_iterator.value.action.type) {
                    case "connector":
                        cacheClassConnectorForState(state_iterator.key, state_iterator.value.action.value);
                        break;

                    case "mapper":
                        cacheMapper(state_iterator.key, state_iterator.value.action.value);
                        break;

                    case "pipeline":
                        cachePipeline(state_iterator.key, state_iterator.value.action.value);
                        break;

                    case "apicall":
                        cacheApiCall(state_iterator.key, state_iterator.value.action.value);
                        break;

                    case "search-single":
                        cacheSearchSingle(state_iterator.key, state_iterator.value.action.value);
                        break;

                    case "search":
                        cacheSearch(state_iterator.key, state_iterator.value.action.value);
                        break;

                    case "update":
                        cacheUpdate(state_iterator.key, state_iterator.value.action.value);
                        break;

                    case "delete":
                        cacheDelete(state_iterator.key, state_iterator.value.action.value);
                        break;

                    case "create":
                        cacheCreate(state_iterator.key, state_iterator.value.action.value);
                        break;

                    default:
                        # in case of invalid data...
                        throw "FSM-INIT-ERROR", sprintf("FSM %y state %y: invalid action type %y; expecting one of "
                            "\"connector\", \"mapper\", or \"pipeline\"", name, state_iterator.value.name,
                            state_iterator.value.action.type);
                }
            }

            if (!state_iterator.value.transitions && !state_iterator.value.hasKey("final")) {
                # mark the state as final if it has no transitions and it's not marked as final by the user
                fsmDefinition.states{state_iterator.key}."final" = True;
            }

            cacheConnectorsInConditions(state_iterator.key, state_iterator.value.transitions);
        }

        # if there is no explicitly defined initial state then consider the first state in the definition initial
        if (!init_states) {
            init_states{fsmDefinition.states.firstKey()} = fsmDefinition.states.firstValue();
        }
    }

    private checkConnectorType(string state, hash<auto> connector_info, hash<auto> expected_types) {
        if (!expected_types.hasKey(connector_info.type)) {
            throw "FSM-INIT-ERROR", sprintf("FSM %y state %y: unexpected connector type: %y, expected type(s): %y",
                name, fsmDefinition.states{state}.name, connector_info.type, keys expected_types);
        }
    }

    # adds an object of the class to the class_pfx_map
    private cacheClassConnectorForState(string state, hash<auto> connector, bool condition = False) {
        hash<auto> connector_info = getClassConnectorInfo(connector);
        if (class_pfx_map{state}{connector."class"} &&
            class_pfx_map{state}{connector."class"}.hasKey(connector.prefix)) {

            QDBG_ASSERT(False);
            return;
        }

        class_pfx_map{state}{connector."class"}{connector.prefix} = True;
        cacheClassAndConnector(connector, connector_info);
        checkConnectorType(state, connector_info, condition ? {CONDITION_CONNECTOR_TYPE: True} :
            ActionConnectorTypes);
    }

    # adds a class connector to the class_connectors map
    private cacheClassAndConnector(hash<auto> connector, hash<auto> connector_info) {
        QDBG_LOG("FsmInfo::cacheClassAndConnector: adding connector: %y", connector);

        Reflection::Class cls;
        if (class_cache.hasKey(connector."class")) {
            cls = class_cache{connector."class"};
        } else {
            Program pgm = getFsmHandler().getInterfaceProgram();
            cls = Reflection::Class::forName(pgm, connector."class");
            class_cache{connector."class"} = cls;
        }

        class_connectors{connector."class"}{connector.connector} = connector_info;
        QDBG_LOG("FsmInfo::cacheClassAndConnector: connector has been added: %y", connector);
    }

    #! returns class connectors info
    private hash<auto> getClassConnectorInfo(hash<auto> connector) {
        QDBG_ASSERT(connector.hasKey("connector"));

        *hash<auto> known_connectors = Qorus.qmm.lookupClass(Qorus.qmm.classId(connector."class")).connectors;
        if (!known_connectors) {
            throw "FSM-INIT-ERROR", sprintf("FSM %y: class %y has no connectors", name, connector."class");
        }

        if (!known_connectors.hasKey(connector.connector)) {
            throw "FSM-INIT-ERROR", sprintf("FSM %y: class %y doesn't contain connector %y, known connectors: %y",
                name, connector."class", connector.connector, known_connectors);
        }

        return known_connectors{connector.connector};
    }

    #! checks if mapper exists with the given name
    private cacheMapper(string state, string name) {
        if (mappers.hasKey(state) && mappers{state}.hasKey(name)) {
            QDBG_ASSERT(False);
            return;
        }
        # will throw an error if mapper doesn't exist
        Mapper::Mapper mapper = get_specific_mapper(name);
        # suppress warning
        QDBG_ASSERT(mapper);
        # don't cache Mapper object
        mappers{state}{name} = True;
    }

    #! adds a pipeline with the given name to the cache
    private cachePipeline(string state, string name) {
        if (pipelines.hasKey(state) && pipelines{state}.hasKey(name)) {
            QDBG_ASSERT(False);
            return;
        }

        *hash<auto> pipeline = Qorus.qmm.lookupPipeline(name);
        if (!pipeline) {
            throw "FSM-INIT-ERROR", sprintf("FSM %y state %y: unknown pipeline %y", self.name,
                fsmDefinition.states{state}.name, name);
        }
        # cache pipeline library
        qorus_load_library(pipeline.lib, _priv_get_pgm_ctx(), sub (string msg) {UserApi::logInfo(vsprintf(msg, argv));});
        pipelines{state}{name} = new QorusPipelineFactory(pipeline + {"options": {"name": name}});
        pipeline_opts{state}{name} = pipeline.options;
    }

    #! adds an API call to the cache
    private cacheApiCall(string state, hash<auto> info) {
        # save path to data provider
        apicalls{state} = {
            "provider": sprintf("%s/%s%s", info.type, info.name, info.path),
            "request_options": info.request_options,
        };
    }

    #! adds a search single state to the cache
    private cacheSearchSingle(string state, hash<auto> info) {
        # save path to data provider
        search_single_map{state} = {
            "provider": sprintf("%s/%s%s", info.type, info.name, info.path),
        };
    }

    #! adds a search state to the cache
    private cacheSearch(string state, hash<auto> info) {
        # save path to data provider
        search_map{state} = {
            "provider": sprintf("%s/%s%s", info.type, info.name, info.path),
        };
    }

    #! adds a update state to the cache
    private cacheUpdate(string state, hash<auto> info) {
        # save path to data provider
        update_map{state} = {
            "provider": sprintf("%s/%s%s", info.type, info.name, info.path),
        };
    }

    #! adds a delete state to the cache
    private cacheDelete(string state, hash<auto> info) {
        # save path to data provider
        delete_map{state} = {
            "provider": sprintf("%s/%s%s", info.type, info.name, info.path),
        };
    }

    #! adds an create state to the cache
    private cacheCreate(string state, hash<auto> info) {
        # save path to data provider
        create_map{state} = {
            "provider": sprintf("%s/%s%s", info.type, info.name, info.path),
        };
    }

    static auto getConfigItemValue(hash<auto> fsm_ctx, string cfg_item, *hash<auto> local_context, bool expand_complex_values) {
        FsmInfo fsm_info = fsm_ctx.fsm;
        hash<auto> new_local_context = local_context + {
            "input": fsm_info.getStateData(fsm_ctx.state, fsm_ctx.exec_id),
        };
        return fsm_info.getConfigItemValue(fsm_ctx.state, cfg_item, new_local_context, expand_complex_values);
    }

    static hash<auto> getConfigItemHash(hash<auto> fsm_ctx, *hash<auto> local_context) {
        FsmInfo fsm_info = fsm_ctx.fsm;
        hash<auto> new_local_context = local_context + {
            "input": fsm_info.getStateData(fsm_ctx.state, fsm_ctx.exec_id),
        };
        return fsm_info.getConfigItemHash(fsm_ctx.state, new_local_context);
    }
}

/**
    This class represents one finite state machine in Qorus (thread safe).
 */
public class Fsm inherits Observer {
    private {
        FsmInfo fsmInfo;

        # sequence for generating ID for execution instances
        Sequence sequence();

        # map of execution instances (key is the ID)
        hash<string, FsmExecution> execInstances;

        AbstractFsmHandler fsmHandler;
    }

    /**
        Constructs a FSM with the given name and FSM definition hash
        @param name the name of the FSM
        @param fsm_definition the FSM info hash according to the YAML schema
        @param fsm_handler AbstractFsmHandler for handling of the state data and FSM transitions

        @throw FSM-INIT-ERROR in case cannot be initialized
     */
    constructor(string name, hash<auto> fsm_definition, AbstractFsmHandler fsm_handler) {
        fsmHandler = fsm_handler;
        fsmInfo = new FsmInfo(self, name, fsm_definition);
        UserApi::logDebug("FSM %y initialized", name);
    }

    #! Returns the first FsmExecution object or @ref nothing if no FSM has been executed
    /**
        @return the first FsmExecution object or @ref nothing if no FSM has been executed
     */
    *FsmExecution getExecutionInstance() {
        return execInstances.firstValue();
    }

    /**
        @param id the id of the FsmExecution to be returned

        @return FsmExecution object

        @throw FSM-EXECUTION-NOT-FOUND in case the FsmExecution object with the given id is not found
     */
    FsmExecution getExecutionInstance(int id) {
        *FsmExecution instance = execInstances{id};
        if (!instance) {
            throw "FSM-EXECUTION-NOT-FOUND", sprintf("FSM %y execution instance id %y not found, known ids: %y",
                getName(), id, (map $1.toInt(), keys execInstances));
        }
        return instance;
    }

    /**
        @return the FsmInfo containing all info about this FSM
     */
    FsmInfo getInfo() {
        return fsmInfo;
    }

    #! Returns the name of the FSM
    string getName() {
        return fsmInfo.getName();
    }

    /**
        @return AbstractFsmHandler
     */
    AbstractFsmHandler getFsmHandler() {
        return fsmHandler;
    }

    /**
        Creates one execution instance of this FSM and runs it syncronously
        @param input_data optional input data

        @return id of the execution FSM instance
     */
    FsmExecution execute(auto input_data) {
        int id = sequence.next();

        FsmExecution instance(id, fsmInfo);
        execInstances{id} = instance;
        UserApi::logDebug("FSM %y exec ID %d created with input data: %y", getName(), id, input_data);

        instance.run(input_data);
        instance.rethrowExceptions();
        return instance;
    }

    FsmExecution executeBlock(auto input_data, string block_name, FsmInfo block_info) {
        int id = sequence.next();

        FsmExecution instance(id, block_info);
        execInstances{id} = instance;
        UserApi::logDebug("FSM %y exec ID %d block %y successfully created with input data: %y", getName(), id,
            block_name, input_data);

        instance.run(input_data);
        instance.rethrowExceptions();
        return instance;
    }

    # implements Observer's update method
    update(string id, hash<auto> data_) {
        UserApi::logInfo("FSM %y event with id %y received", getName(), id);
        UserApi::logDebug("FSM %y event data: %N", getName(), data_);

        execute((data_,));
    }
}

/**
    This class represents one execution of finite state machine in Qorus (thread safe).
 */
public class FsmExecution {
    private {
        int id;

        FsmInfo fsmInfo;

        # id of a state -> number of flows
        hash<auto> currentStates;

        bool running;

        FsmStrategy strategy;
    }

    /**
        Constructs a FsmExecution from the given FsmInfo and optional input data
        @param fsm_info the FsmInfo object
     */
    constructor(int id, FsmInfo fsm_info) {
        self.id = id;
        fsmInfo = fsm_info;
        running = False;

        # create a concrete strategy based on the given options
        *string action_strategy = fsmInfo.getOption("action-strategy");
        switch (action_strategy) {
            case "all":
                strategy = new FsmAllStatesStrategy(self);
                break;
            default:
                strategy = new FsmOneStateStrategy(self);
                break;
        }
    }

    /**
        Runs this FsmExecution
        @param input_data optional input data

        @return the list of all exceptions happened in the background threads if any

        @throw FSM-EXECUTION-ERROR in case it cannot be executed

        @note input data will be unpacked
     */
    run(auto input_data) {
        if (isRunning()) {
            throw "FSM-EXECUTION-ERROR", sprintf("FSM %y: execution instance %d is already running",
                fsmInfo.getName(), id);
        }

        setRunning(True);
        on_exit setRunning(False);

        if (input_data.typeCode() == NT_LIST && (elements input_data == 1)) {
            input_data = input_data[0];
            QDBG_LOG("unpacked input data: %y", input_data);
        }

        UserApi::logDebug("FSM %y exec ID %d input data: %y", fsmInfo.getName(), id, input_data);

        # verify input data
        *AbstractDataProviderType input_type = fsmInfo.getInputType();
        if (input_type) {
            input_data = input_type.acceptsValue(input_data);
        }

        foreach hash<auto> i in (fsmInfo.getInitialStates().pairIterator()) {
            currentStates{i.key} = 1;
            QDBG_LOG("FsmExecution::run() i: %y", i);
            fsmInfo.getFsmHandler().setStateData(fsmInfo.getName(), id, i.value.id, input_data);
            QDBG_LOG("FsmExecution::run() state %y (%y, %y, %y) init data: %y", i.key, fsmInfo.getName(), id,
                i.value.id, fsmInfo.getFsmHandler().getStateData(fsmInfo.getName(), id, i.value.id));
        }

        QDBG_LOG("FsmExecution::run() initStates: %y", currentStates);

        *hash<ExceptionInfo> exception_info;
        while (currentStates) {
            if (!isRunning()) {
                break;
            }
            try {
                currentStates = strategy.execute(currentStates);
                exception_info = strategy.getThreadExceptionInfo();
            } catch (hash<ExceptionInfo> ex) {
                UserApi::logError("FSM %y exec ID error: %s", fsmInfo.getName(), id, get_exception_string(ex));
                exception_info = ex;
            }
            if (exception_info) {
                UserApi::logError("FSM %y exec ID %d stopping due to errors", fsmInfo.getName(), id);
                stop();
            }
        }

        if (exception_info) {
            UserApi::logError("FSM %y exec ID %d finished with errors: %s: %s (see above for full stack trace",
                fsmInfo.getName(), id, exception_info.err, exception_info.desc);
        } else {
            UserApi::logDebug("FSM %y exec ID %d finished successfully", fsmInfo.getName(), id);
        }
    }

    #! Returns the result of executing the FSM
    auto getResult() {
        auto rv = strategy.getResult();

        # verify output data
        *AbstractDataProviderType output_type = fsmInfo.getOutputType();
        if (output_type) {
            rv = output_type.acceptsValue(rv);
        }

        return rv;
    }

    #! Rethrows any exception thrown while executing the FSM
    rethrowExceptions() {
        *hash<ExceptionInfo> ex = strategy.getThreadExceptionInfo();
        # FIXME: only throws the top-level exception
        if (ex) {
            throw ex.err, ex.desc, ex.arg;
        }
    }

    /**
        Stops this FsmExecution
     */
    stop() {
        UserApi::logInfo("FSM %y exec ID %d stopping", fsmInfo.getName(), id);
        setRunning(False);
        UserApi::logInfo("FSM %y exec ID %d stopped", fsmInfo.getName(), id);
    }

    #! sets running flag
    private setRunning(bool value) {
        running = value;
    }

    /**
        @return True if the instance is running
     */
    bool isRunning() {
        return running;
    }

    /**
        @return id of the instance
     */
    int getId() {
        return id;
    }

    /**
        @return the FsmInfo containing all info about the FSM
     */
    FsmInfo getInfo() {
        return fsmInfo;
    }

    /**
        Resets the FsmExecution so that it can be run again. Clears all state data.
     */
    reset() {
        UserApi::logInfo("FSM %y exec ID %d resetting", fsmInfo.getName(), id);
        setRunning(False);
        fsmInfo.getFsmHandler().clearStateData(fsmInfo.getName(), id);
        UserApi::logInfo("FSM %y exec ID %d reset", fsmInfo.getName(), id);
    }
}

/**
    This class is a base class for different strategies on FSM execution (see Strategy pattern)
 */
class FsmStrategy {
    private:internal {
        Mutex newStatesMutex();
        hash<auto> newStates = {};

        Mutex expr_lck();
        hash<string, Expression> qore_expr_map = {};
    }

    private {
        FsmInfo fsmInfo;
        FsmExecution fsmExecution;
        int maxNumberOfThreads = 1;

        Mutex threadExceptionsMutex();
        hash<ExceptionInfo> threadExceptionInfo;

        # the last result of any state in the FSM execution; the result of FSM execution
        auto last_result;

        # default data pipeline bulk processing row size
        const DefaultBulkRowSize = 1000;
    }

    /**
        @param fsm_execution FsmExecution object
     */
    constructor(FsmExecution fsm_execution) {
        fsmExecution = fsm_execution;
        fsmInfo = fsmExecution.getInfo();
        maxNumberOfThreads = fsmInfo.getOption("max-thread-count") ?? maxNumberOfThreads;
    }

    #! Returns the last result of executing the FSM strategy
    auto getResult() {
        return last_result;
    }

    #! Returns the FSM execution ID
    int getExecId() {
        return fsmExecution.getId();
    }

    /**
        @return the list of exceptions happened in threads
     */
    *hash<ExceptionInfo> getThreadExceptionInfo() {
        threadExceptionsMutex.lock();
        on_exit threadExceptionsMutex.unlock();

        return threadExceptionInfo;
    }

    /**
        Executes current actions and based on the concrete strategy used performs state transitions
        @param current_states current state data
     */
    hash<auto> execute(hash<auto> current_states) {
        QDBG_LOG("FsmStrategy::execute() executing FsmStrategy for %y (ctx: %y)", fsmInfo.getName(),
            tld.getContext());
        QDBG_LOG("FsmStrategy::execute() currentStates: %y", current_states);

        hash<auto> tld_copy = hash(tld);

        foreach string current_state in (keys current_states) {
            try {
                FsmStateContextHelper fsch(fsmInfo, current_state, fsmExecution.getId());
                QDBG_LOG("FsmStrategy::execute() submit: current_state: %y", current_state);
                hash<auto> state_info = fsmInfo.getStateInfo(current_state);
                QDBG_LOG("FsmStrategy::execute() submit: ctx: %y (%y) state_info: %y", tld.getContext(),
                    tld._current_ix, state_info);

                if (state_info.action) {
                    for (int i = 0; i < current_states{current_state}; ++i) {
                        runOneStateAction(state_info, tld_copy);
                    }
                } else if (state_info.type == "fsm") {
                    for (int i = 0; i < current_states{current_state}; ++i) {
                        runOneStateFsm(state_info, tld_copy);
                    }
                } else if (state_info.type == "block") {
                    for (int i = 0; i < current_states{current_state}; ++i) {
                        runOneStateBlock(state_info, tld_copy);
                    }
                } else if (state_info.type == "if") {
                    # the if state is only run once
                    bool if_result = runOneStateIf(state_info, tld_copy);
                    QDBG_ASSERT(state_info.if_transition);
                    # execute transition if available
                    if (*hash<auto> transition = state_info.if_transition{if_result ? "true" : "false"}) {
                        # get state data for transition
                        auto state_data = fsmInfo.getFsmHandler().getStateData(fsmInfo.getName(),
                            fsmExecution.getId(), state_info.id);
                        makeStateTransitionInternal(state_info, state_data, transition);
                    }
                    continue;
                }
                concreteStrategy1(current_state);
            } catch (hash<ExceptionInfo> ex) {
                makeOneStateErrorTransition(current_state, ex);
            }
        }

        if (threadExceptionInfo) {
            return current_states;
        }

        concreteStrategy2(\current_states, tld_copy);

        current_states = newStates;
        newStates = {};

        return current_states;
    }

    #! override this method to provide concrete strategy implementation
    abstract private concreteStrategy1(string current_state);

    #! override this method to provide concrete strategy implementation
    abstract private concreteStrategy2(reference<hash> current_states, hash<auto> new_tld);

    #! calls the given connector with the given data
    private auto callConnector(hash<auto> state_info, hash<auto> connector, auto data_) {
        hash<auto> connector_info = fsmInfo.getClassConnector(connector."class", connector.connector);
        auto connector_object = fsmInfo.createClassObject(state_info, connector."class", connector.prefix);

        QDBG_LOG("FsmStrategy::callConnector() calling %s%s::%s", connector.prefix, connector."class",
            connector_info.method);
        return call_object_method(connector_object, connector_info.method, data_);
    }

    private auto callMapper(hash<auto> state_info, string name, auto data_) {
        Mapper::Mapper mapper = fsmInfo.getMapper(state_info, name);
        QDBG_LOG("FsmStrategy::callMapper() %s (data: %y)", name, data_.fullType());
        auto rv = mapper.mapAuto(data_);
        int count = mapper.getCount();
        UserApi::logInfo("FSM %y state %y exec ID %d: %d record%s processed with mapper %y", fsmInfo.getName(),
            state_info.name, fsmExecution.getId(), count, count == 1 ? "" : "s", name);
        return rv;
    }

    private callPipeline(hash<auto> state_info, string name, auto data_, hash<auto> new_tld) {
        QDBG_LOG("FsmStrategy::callPipeline() %y: state: %y", name, state_info.name);

        QorusPipelineFactory pipeline_factory = fsmInfo.getPipeline(state_info.key, name);

        hash<PipelineOptionInfo> opts = pipeline_factory.getInfo().opts + <PipelineOptionInfo>{
            "info_log": sub (string fmt) { UserApi::logInfo("FSM %y exec ID %d: %s", fsmInfo.getName(),
                fsmExecution.getId(), vsprintf(fmt, argv)); },
            "error_log": sub (string fmt) { UserApi::logInfo("FSM %y exec ID %d: %s", fsmInfo.getName(),
                fsmExecution.getId(), vsprintf(fmt, argv)); },
            "debug_log": sub (string fmt) { UserApi::logInfo("FSM %y exec ID %d: %s", fsmInfo.getName(),
                fsmExecution.getId(), vsprintf(fmt, argv)); },
            "thread_callback": sub() {ThreadLocalData::replace(new_tld);},
        };

        DataProviderPipeline pipeline = pipeline_factory.create(opts);

        # check for input data provider
        *hash<auto> pipe_opts = fsmInfo.getPipelineOptions(state_info.key, name);
        if (*hash<auto> input = pipe_opts."input-provider") {
            UserApi::logInfo("FSM %y state %y exec ID %d using input provider %y for initial pipeline input",
                fsmInfo.getName(), state_info.name, fsmExecution.getId(), input);
            doInput(state_info, name, pipeline, input, pipe_opts."input-provider-options", data_);
        } else {
            QDBG_LOG("FsmStrategy::callPipeline() %y: submitting data to pipeline %y: %y", name, pipeline.getName(),
                data_);
            pipeline.submit(data_);
        }
        QDBG_LOG("FsmStrategy::callPipeline() %y: waiting for pipeline %y to complete", name, pipeline.getName());
        pipeline.waitDone();
        QDBG_LOG("FsmStrategy::callPipeline() %y: pipeline %y completed", name, pipeline.getName());
    }

    private auto callApi(hash<auto> state_info, auto data_) {
        QDBG_LOG("FsmStrategy::callApi() state: %y", state_info.name);
        string provider_path;
        hash<auto> request_options;
        AbstractDataProvider provider = fsmInfo.getDataProviderForApiCallState(state_info.key, \provider_path,
            \request_options);
        if (!provider.supportsRequest()) {
            throw "API-CALL-ERROR", sprintf("FSM %y state %y exec ID %d: API call state specifies data provider "
                "%y (%s) which does not support the request-response integration pattern", fsmInfo.getName(),
                state_info.name, fsmExecution.getId(), provider_path, provider.getName());
        }

        # make the API call and return the response as the output data
        auto args;
        if (state_info.action.value.use_args) {
            QDBG_LOG("FsmStrategy::callApi() apicall config args: %y", state_info.action.value.args);
            switch (state_info.action.value.args.type) {
                case "hash": {
                    args = map {
                        $1.key: $1.value.value.typeCode() == NT_STRING && $1.value.type != "string"
                            && $1.value.value !~ /^\$/ ? parse_yaml($1.value.value) : $1.value.value
                    }, state_info.action.value.args.value.pairIterator();
                    break;
                }
                default: {
                    if (state_info.action.value.args.value.typeCode() == NT_STRING
                        && state_info.action.value.args.type != "string"
                        && state_info.action.value.args.value !~ /^\$/) {
                        args = parse_yaml(state_info.action.value.args.value);
                    } else if (state_info.action.value.args.value.type() == state_info.action.value.args.type) {
                        args = state_info.action.value.args.value;
                    } else {
                        throw "API-CALL-ERROR", sprintf("FSM %y state %y exec ID %d: API call state specifies type "
                            "%y, but value has type %y", fsmInfo.getName(), state_info.name, fsmExecution.getId(),
                            state_info.action.value.args.type, state_info.action.value.args.value);
                    }
                }
            }
            QDBG_LOG("FsmStrategy::callApi() apicall args: %y", args);
            args = UserApi::expandTemplatedValue(args, UserApi::getUserContextInfo());
        } else {
            args = data_;
        }
        UserApi::logInfo("FSM %y state %y exec ID %d: call API on request-response data provider %y (%s) (args "
            "type: %s)", fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, provider.getName(),
            args.fullType());
        UserApi::logDebug("FSM %y state %y exec ID %d: API call on %y (%s) request: %y", fsmInfo.getName(),
            state_info.name, fsmExecution.getId(), provider_path, provider.getName(), args);
        date start = now_us();
        on_error rethrow $1.err, sprintf("FSM %y state %y exec ID %d: (%y API call duration: %y) %s",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, (now_us() - start), $1.desc);
        auto rv = provider.doRequest(args, request_options);

        UserApi::logDebug("FSM %y state %y exec ID %d: API call on %y (%s) response: %y", fsmInfo.getName(),
            state_info.name, fsmExecution.getId(), provider_path, provider.getName(), rv);
        UserApi::logInfo("FSM %y state %y exec ID %d: API call on %y (%s) response type: %y duration: %y",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, provider.getName(),
            rv.fullType(), (now_us() - start));

        return rv;
    }

    private *hash<auto> searchSingle(hash<auto> state_info, auto data_) {
        QDBG_LOG("FsmStrategy::searchSingle() state: %y", state_info.name);
        string provider_path;
        AbstractDataProvider provider = fsmInfo.getDataProviderForSearchSingleState(state_info.key, \provider_path);
        if (!provider.supportsRead()) {
            throw "SEARCH-SINGLE-ERROR", sprintf("FSM %y state %y exec ID %d: \"search single\" state specifies data "
                "provider %y (%s) which does not support reading or searching records", fsmInfo.getName(),
                state_info.name, fsmExecution.getId(), provider_path, provider.getName());
        }

        # make the single record search and return the response as the output data
        QDBG_LOG("FsmStrategy::searchSingle() config search args: %y search options: %y",
            state_info.action.value.search_args, state_info.action.value.search_options);
        hash<auto> ctxt = UserApi::getUserContextInfo();
        hash<auto> where_cond = getWhereCond(state_info.action.value.search_args, ctxt);
        *hash<auto> search_options = getSearchOptions(state_info.action.value.search_options, ctxt);
        *hash<auto> search_options_orig = search_options;
        *bool requires_result = remove search_options.requires_result;
        QDBG_LOG("FsmStrategy::searchSingle() search args: %y search options: %y",
            state_info.action.value.search_args, state_info.action.value.search_options);
        UserApi::logInfo("FSM %y state %y exec ID %d: \"search single\" on record-based data provider %y (%s) ("
            "where_cond: %y search_options: %y)", fsmInfo.getName(), state_info.name, fsmExecution.getId(),
            provider_path, provider.getName(), where_cond, search_options_orig);
        date start = now_us();
        on_error rethrow $1.err, sprintf("FSM %y state %y exec ID %d: (%y \"search single\" duration: %y) %s",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, (now_us() - start), $1.desc);
        *hash<auto> rv = provider.searchSingleRecord(where_cond, search_options);
        UserApi::logInfo("FSM %y state %y exec ID %d: \"search single\" on %y (%s) response: %y duration: %y",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, provider.getName(),
            rv, (now_us() - start));
        if (!rv && requires_result) {
            throw "SEARCH-SINGLE-RESULT-ERROR", sprintf("no row returned from dataprovider %y with query args %y, "
                "and \"requires_result\" is True", provider_path, where_cond);
        }
        return rv;
    }

    private *list<hash<auto>> search(hash<auto> state_info, auto data_) {
        QDBG_LOG("FsmStrategy::search() state: %y", state_info.name);
        string provider_path;
        AbstractDataProvider provider = fsmInfo.getDataProviderForSearchState(state_info.key, \provider_path);
        if (!provider.supportsRead()) {
            throw "SEARCH-ERROR", sprintf("FSM %y state %y exec ID %d: search state specifies data "
                "provider %y (%s) which does not support reading or searching records", fsmInfo.getName(),
                state_info.name, fsmExecution.getId(), provider_path, provider.getName());
        }

        # make the record search and return the response as the output data
        QDBG_LOG("FsmStrategy::search() config search args: %y search options: %y",
            state_info.action.value.search_args, state_info.action.value.search_options);
        hash<auto> ctxt = UserApi::getUserContextInfo();
        *hash<auto> where_cond = getWhereCond(state_info.action.value.search_args, ctxt);
        *hash<auto> search_options = getSearchOptions(state_info.action.value.search_options, ctxt);
        *hash<auto> search_options_orig = search_options;
        *bool requires_result = remove search_options.requires_result;
        *int max_records = remove search_options.max_records;
        QDBG_LOG("FsmStrategy::search() search args: %y search options: %y",
            state_info.action.value.search_args, state_info.action.value.search_options);
        UserApi::logInfo("FSM %y state %y exec ID %d: search on record-based data provider %y (%s) ("
            "where_cond: %y search_options: %y)", fsmInfo.getName(), state_info.name, fsmExecution.getId(),
            provider_path, provider.getName(), where_cond, search_options_orig);
        date start = now_us();
        on_error rethrow $1.err, sprintf("FSM %y state %y exec ID %d: (%y search duration: %y) %s",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, (now_us() - start), $1.desc);
        AbstractDataProviderRecordIterator i = provider.searchRecords(where_cond, search_options);
        *list<hash<auto>> rv = map $1, i;
        UserApi::logInfo("FSM %y state %y exec ID %d: search on %y (%s) rows returned: %d duration: %y",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, provider.getName(),
            rv.size(), (now_us() - start));
        if (!rv && requires_result) {
            throw "SEARCH-RESULT-ERROR", sprintf("no data returned from dataprovider %y with query args %y, "
                "and \"requires_result\" is True", provider_path, where_cond);
        }
        if (max_records && rv.size() > max_records) {
            throw "SEARCH-RESULT-ERROR", sprintf("dataprovider %y with query args %y returned %d records, "
                "but \"max_records\" = %d", provider_path, where_cond, rv.size(), max_records);
        }
        return rv;
    }

    private hash<auto> update(hash<auto> state_info, auto data_) {
        QDBG_LOG("FsmStrategy::update() state: %y", state_info.name);
        string provider_path;
        AbstractDataProvider provider = fsmInfo.getDataProviderForUpdateState(state_info.key, \provider_path);
        if (!provider.supportsUpdate()) {
            throw "UPDATE-ERROR", sprintf("FSM %y state %y exec ID %d: update state specifies data "
                "provider %y (%s) which does not support updating records", fsmInfo.getName(),
                state_info.name, fsmExecution.getId(), provider_path, provider.getName());
        }

        # make the record update and return the response as a hash of the number of rows updated
        QDBG_LOG("FsmStrategy::update() config update: %y search args: %y search options: %y",
            state_info.action.value.update_args, state_info.action.value.search_args,
            state_info.action.value.search_options);
        hash<auto> ctxt = UserApi::getUserContextInfo();
        hash<auto> update = getRecordHash(state_info.action.value, "update_args", ctxt);
        *hash<auto> where_cond = getWhereCond(state_info.action.value.search_args, ctxt);
        *hash<auto> search_options = getSearchOptions(state_info.action.value.search_options, ctxt);
        *hash<auto> search_options_orig = search_options;
        *bool requires_result = remove search_options.requires_result;
        QDBG_LOG("FsmStrategy::update() update search args: %y search options: %y",
            state_info.action.value.search_args, state_info.action.value.search_options);
        UserApi::logInfo("FSM %y state %y exec ID %d: update record-based data provider %y (%s) ("
            "update: %y where_cond: %y search_options: %y)", fsmInfo.getName(), state_info.name,
            fsmExecution.getId(), provider_path, provider.getName(), update, where_cond, search_options_orig);
        date start = now_us();
        on_error rethrow $1.err, sprintf("FSM %y state %y exec ID %d: (%y update duration: %y) %s",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, (now_us() - start), $1.desc);
        int records_affected = provider.updateRecords(update, where_cond, search_options);
        UserApi::logInfo("FSM %y state %y exec ID %d: update %y (%s) records updated: %d duration: %y",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, provider.getName(),
            records_affected, (now_us() - start));
        if (!records_affected && requires_result) {
            throw "UPDATE-RESULT-ERROR", sprintf("no records updated in dataprovider %y with set: %y where: %y, "
                "and \"requires_result\" is True", provider_path, update, where_cond);
        }
        return {"records_affected": records_affected};
    }

    private hash<auto> deleteRecords(hash<auto> state_info, auto data_) {
        QDBG_LOG("FsmStrategy::deleteRecords() state: %y", state_info.name);
        string provider_path;
        AbstractDataProvider provider = fsmInfo.getDataProviderForDeleteState(state_info.key, \provider_path);
        if (!provider.supportsDelete()) {
            throw "DELETE-ERROR", sprintf("FSM %y state %y exec ID %d: delete state specifies data "
                "provider %y (%s) which does not support deleting records", fsmInfo.getName(),
                state_info.name, fsmExecution.getId(), provider_path, provider.getName());
        }

        # make the deleting operation and return the response as a hash of the number of rows deleted
        QDBG_LOG("FsmStrategy::deleteRecords() config delete search args: %y search options: %y",
            state_info.action.value.search_args, state_info.action.value.search_options);
        hash<auto> ctxt = UserApi::getUserContextInfo();
        *hash<auto> where_cond = getWhereCond(state_info.action.value.search_args, ctxt);
        *hash<auto> search_options = getSearchOptions(state_info.action.value.search_options, ctxt);
        *hash<auto> search_options_orig = search_options;
        *bool requires_result = remove search_options.requires_result;
        QDBG_LOG("FsmStrategy::deleteRecords() delete args: %y search options: %y",
            state_info.action.value.search_args, state_info.action.value.search_options);
        UserApi::logInfo("FSM %y state %y exec ID %d: delete in record-based data provider %y (%s) ("
            "where_cond: %y search_options: %y)", fsmInfo.getName(), state_info.name,
            fsmExecution.getId(), provider_path, provider.getName(), where_cond, search_options_orig);
        date start = now_us();
        on_error rethrow $1.err, sprintf("FSM %y state %y exec ID %d: (%y delete duration: %y) %s",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, (now_us() - start), $1.desc);
        int records_affected = provider.deleteRecords(where_cond, search_options);
        UserApi::logInfo("FSM %y state %y exec ID %d: delete in %y (%s) records deleted: %d duration: %y",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, provider.getName(),
            records_affected, (now_us() - start));
        if (!records_affected && requires_result) {
            throw "DELETE-RESULT-ERROR", sprintf("no records deleted in dataprovider %y with where: %y, "
                "and \"requires_result\" is True", provider_path, where_cond);
        }
        return {"records_affected": records_affected};
    }

    private list<hash<auto>> create(hash<auto> state_info, auto data_) {
        QDBG_LOG("FsmStrategy::create() state: %y", state_info.name);
        string provider_path;
        AbstractDataProvider provider = fsmInfo.getDataProviderForCreateState(state_info.key, \provider_path);
        if (!provider.supportsCreate()) {
            throw "UPDATE-ERROR", sprintf("FSM %y state %y exec ID %d: create state specifies data "
                "provider %y (%s) which does not support creating records", fsmInfo.getName(),
                state_info.name, fsmExecution.getId(), provider_path, provider.getName());
        }

        # make the record update and return the response as a hash of the number of rows updated
        QDBG_LOG("FsmStrategy::create() config create (type: %s): %y", state_info.action.value.create_args ?
            "standard" : "freeform", state_info.action.value.create_args ??
            state_info.action.value.create_args_freeform);
        hash<auto> ctxt = UserApi::getUserContextInfo();
        list<hash<auto>> create_args = getCreateRecords(state_info.action.value, ctxt);
        UserApi::logInfo("FSM %y state %y exec ID %d: create record-based data provider %y (%s) "
            "(create: %d record%s)", fsmInfo.getName(), state_info.name,
            fsmExecution.getId(), provider_path, provider.getName(), create_args.size(),
            create_args.size() == 1 ? "" : "s");
        date start = now_us();
        on_error rethrow $1.err, sprintf("FSM %y state %y exec ID %d: (%y create duration: %y) %s",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, (now_us() - start), $1.desc);
        list<hash<auto>> rv = map provider.createRecord($1), create_args;
        UserApi::logInfo("FSM %y state %y exec ID %d: create %y (%s) records createed: %d duration: %y",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), provider_path, provider.getName(),
            rv.size(), (now_us() - start));
        return rv;
    }

    private *hash<auto> getWhereCond(*hash<auto> h, hash<auto> ctxt) {
        hash<auto> rv;
        foreach hash<auto> i in (h.pairIterator()) {
            auto arg = i.value.value.typeCode() == NT_STRING && i.value.type != "string" && i.value.value !~ /^\$/
                ? parse_yaml(i.value.value)
                : i.value.value;
            if (i.value.op.typeCode() == NT_LIST) {
                # only a single nesting is currently supported
                switch (i.value.op.lsize()) {
                    case 1:
                        rv{i.key} = {
                            "op": i.value.op[0],
                            "arg": UserApi::expandTemplatedValue(arg, ctxt),
                        };
                        break;

                    case 2:
                        rv{i.key} = {
                            "op": i.value.op[0],
                            "arg": {
                                "op": i.value.op[1],
                                "arg": UserApi::expandTemplatedValue(arg, ctxt),
                            },
                        };
                        break;

                    default:
                        throw "SEARCH-ARG-ERROR", sprintf("only a single operator nesting level is allowed; got %d "
                            "levels (%y)", i.value.op.lsize(), i.value.op);
                }
            } else {
                rv{i.key} = {
                    "op": i.value.op,
                    "arg": UserApi::expandTemplatedValue(arg, ctxt),
                };
            }
        }
        return rv;
    }

    private *hash<auto> getSearchOptions(*hash<auto> opts, hash<auto> ctxt) {
        if (!opts) {
            return;
        }
        return map {
            $1.key: $1.value.value.typeCode() == NT_STRING && $1.value.type != "string" && $1.value.value !~ /^\$/
                ? parse_yaml($1.value.value) : $1.value.value
        }, UserApi::expandTemplatedValue(opts, ctxt).pairIterator();
    }

    private hash<auto> getRecordHash(hash<auto> config, string arg, hash<auto> ctxt) {
        *hash<auto> h = config{arg};
        if (!h) {
            string err = arg;
            err =~ s/_/-/;
            err =~ tr/a-z/A-Z/;
            throw err + "-ARG-ERROR", sprintf("missing input option %y", arg);
        }

        return map {
            $1.key: $1.value.value.typeCode() == NT_STRING && $1.value.type != "string" && $1.value.value !~ /^\$/
                ? parse_yaml($1.value.value)
                : $1.value.value
        }, UserApi::expandTemplatedValue(h, ctxt).pairIterator();
    }

    private list<hash<auto>> getCreateRecords(hash<auto> config, hash<auto> ctxt) {
        auto l = config.create_args;
        bool freeform;
        if (!l && (l = config.create_args_freeform)) {
            freeform = True;
        }
        if (!l) {
            throw "CREATE-ARG-ERROR", "missing options \"create_args\" and \"create_args_freeform\"";
        }

        l = UserApi::expandTemplatedValue(l, ctxt);
        if (freeform) {
            switch (l.typeCode()) {
                case NT_LIST:
                    break;
                case NT_HASH:
                    l = (l,);
                    break;
                default:
                    throw "CREATE-ARG-ERROR", sprintf("option \"create_args_freeform\" has value %y; expecting "
                        "\"hash\"", l.fullType());
            }
        }
        list<hash<auto>> rv;
        foreach auto record in (l) {
            if (record.typeCode() != NT_HASH) {
                throw "CREATE-ARG-ERROR", sprintf("create record entry %d/%d is type %y; expecting \"hash\"", $# + 1, l.size(),
                    record.fullType());
            }
            if (freeform) {
                rv += record;
            } else {
                rv += map {
                    $1.key: $1.value.value.typeCode() == NT_STRING && $1.value.type != "string" && $1.value.value !~ /^\$/
                        ? parse_yaml($1.value.value)
                        : $1.value.value
                }, record.pairIterator();
            }
        }
        return rv;
    }

    private doInput(hash<auto> state_info, string name, DataProviderPipeline pipeline, hash<auto> input,
            *hash<auto> options, auto data_) {
        AbstractDataProvider prov;

        # check subtype
        switch (input.subtype) {
            case "request":
            case "record":
            case NOTHING:
                break;

            default:
                throw "INPUT-PROVIDER-ERROR", sprintf("FSM %y state %y: %s: pipeline %y: invalid subtype in %y",
                    fsmInfo.getName(), state_info.name, name, pipeline.getName(), input);
        }

        # ensure path is prefixed with "/"
        if (input.path && input.path !~ /^\//) {
            input.path = "/" + input.path;
        }

        switch (input.type) {
            case "connection":
                prov = getProviderFromConnection(input.name + input.path, Qorus.connections);
                break;

            case "datasource":
                prov = getProviderFromConnection(input.name + input.path, Qorus.dsmanager);
                break;

            case "remote":
                prov = getProviderFromConnection(input.name + input.path, Qorus.remotemonitor);
                break;

            case "factory": {
                *hash<auto> factory_options = map {$1.key: $1.value.value}, input.options.pairIterator();
                if (factory_options) {
                    hash<auto> local_context = {"input": data_};
                    factory_options = UserApi::expandTemplatedValue(factory_options, local_context);
                }
                QDBG_LOG("factory %y opts: %y", input.name + input.path, factory_options);

                prov = getProviderFromFactory(input.name + input.path, factory_options);
                break;
            }

            default:
                throw "INPUT-PROVIDER-ERROR", sprintf("FSM %y state %y: %s: pipeline %y: invalid type in %y", name,
                    fsmInfo.getName(), state_info.name, pipeline.getName(), input);
        }

        bool bulk;
        if (prov.supportsBulkRead()) {
            if (!pipeline.getInfo().bulk) {
                UserApi::logInfo("FSM %y state %y exec ID %d %s: pipeline %y: input provider %y supports the bulk "
                    "API but pipeline does not; using single record operations", fsmInfo.getName(), state_info.name,
                    fsmExecution.getId(), name, pipeline.getName(), prov.getName());
            } else {
                UserApi::logInfo("FSM %y state %y exec ID %d %s: pipeline %y: input provider %y and pipeline support "
                    "the bulk API; using bulk operations for maximum performance", fsmInfo.getName(), state_info.name,
                    fsmExecution.getId(), name, pipeline.getName(), prov.getName());
                bulk = True;
            }
        } else {
            if (pipeline.getInfo().bulk) {
                UserApi::logInfo("FSM %y state %y exec ID %d %s: pipeline %y: input provider %y does not support the "
                    "bulk API but pipeline does; using single record operations", fsmInfo.getName(), state_info.name,
                    fsmExecution.getId(), name, pipeline.getName(), prov.getName());
            } else {
                UserApi::logInfo("FSM %y state %y exec ID %d %s: pipeline %y: neither input provider %y nor pipeline "
                    "support the bulk API; using single record operations", fsmInfo.getName(), state_info.name,
                    fsmExecution.getId(), name, pipeline.getName(), prov.getName());
            }
        }

        UserApi::logInfo("FSM %y state %y exec ID %d input provider %y search: %y (opts: %y, bulk: %y)",
            fsmInfo.getName(), state_info.name, fsmExecution.getId(), prov.getName(), options.input_provider_search,
            options.input_search_options, bulk);

        if (bulk) {
            pipeline.submit(prov.searchRecordsBulk(options.input_provider_bulk ?? DefaultBulkRowSize,
                options.input_provider_search, options.input_search_options));
        } else {
            pipeline.submit(prov.searchRecords(options.input_provider_search, options.input_search_options));
        }
    }

    private AbstractDataProvider getProviderFromConnection(string connection_name, object connserver) {
        list<string> connection_path = connection_name.split("/");
        connection_name = shift connection_path;
        AbstractDataProvider rv = connserver.getDataProvider(connection_name);
        map rv = rv.getChildProviderEx($1), connection_path;
        return rv;
    }

    private AbstractDataProvider getProviderFromFactory(string factory_name, *hash<auto> provider_create_options) {
        *list<string> provider_path = factory_name.split("/");
        factory_name = shift provider_path;
        AbstractDataProviderFactory factory = DataProvider::getFactoryEx(factory_name);

        AbstractDataProvider rv = factory.create(provider_create_options);
        map rv = rv.getChildProviderEx($1), provider_path;
        return rv;
    }

    #! evaluates the given expression
    auto evaluateExpression(hash<auto> state_info, auto expression, string lang = "qore", string label,
            auto input_data) {
        QDBG_LOG("FsmStrategy::evaluateExpression() (%s) %y with label: %s", lang, expression, label);

        # issue #3798: resolve the template as a Qore expression if lang == qore
        auto rv = UserApi::expandTemplatedValue(expression, {"input": input_data}, True, NOTHING,
            lang == "qore" ? "qore-expr" : NOTHING);

        if (rv.typeCode() != NT_STRING) {
            UserApi::logDebug("FSM %y state %y exec ID %d expression is type %y: %y; not evaluating as %s code; "
                "using value directly", fsmInfo.getName(), state_info.name, fsmExecution.getId(), rv, rv.type(), lang);
            return rv;
        }
        expression = rv;

        try {
            if (lang == "python") {
                Program pgm = fsmInfo.getFsmHandler().getInterfaceProgram();
                rv = pgm.callFunction("_qorus_python_eval_expr", expression);
            } else {
                # must be a qore expression
                *Expression program_expression = qore_expr_map{expression};
                if (!program_expression) {
                    expr_lck.lock();
                    on_exit expr_lck.unlock();

                    # try again inside the lock
                    program_expression = qore_expr_map{expression};
                    if (!program_expression) {
                        Program pgm = fsmInfo.getFsmHandler().getInterfaceProgram();
                        program_expression = qore_expr_map{expression} = pgm.getExpression(expression, label);
                    }
                }
                rv = program_expression.eval();
            }
        } catch (hash<ExceptionInfo> ex) {
            throw ex.err, sprintf("lang %y expr %y: %s", lang, expression, ex.desc), ex.arg;
        }
        UserApi::logDebug("FSM %y state %y exec ID %d %s expression %y evaluated to: %y", fsmInfo.getName(),
            state_info.name, fsmExecution.getId(), lang, expression, rv);
        return rv;
    }

    #! runs one block state
    private runOneStateBlock(hash<auto> state_info, hash<auto> new_tld) {
        auto input_data = fsmInfo.getFsmHandler().getStateData(fsmInfo.getName(), fsmExecution.getId(), state_info.id);
        FsmStateInputDataContextHelper fsch(input_data);

        QDBG_LOG("executing block state %y ID %y: %y", state_info.key, state_info.id, state_info.name);
        auto result = fsmInfo.executeBlock(state_info, input_data, self);
        QDBG_LOG("block %y result: %N", state_info.name, result);

        # set state result data
        fsmInfo.getFsmHandler().setStateData(fsmInfo.getName(), fsmExecution.getId(), state_info.id, result);
        last_result = result;
    }

    #! runs one if state
    private bool runOneStateIf(hash<auto> state_info, hash<auto> new_tld) {
        auto input_data = fsmInfo.getFsmHandler().getStateData(fsmInfo.getName(), fsmExecution.getId(), state_info.id);
        FsmStateInputDataContextHelper fsch(input_data);

        QDBG_LOG("executing if state %y ID %y: %y", state_info.key, state_info.id, state_info.name);
        string label = fsmInfo.getName() + ":" + state_info.id;
        auto result = evaluateExpression(state_info, state_info.condition, state_info.language ?? "qore", label,
            input_data);
        result = result.toBool();
        QDBG_LOG("if %y result: %y", state_info.name, result);
        return result;
    }

    #! runs one given action
    private runOneStateFsm(hash<auto> state_info, hash<auto> new_tld) {
        auto input_data = fsmInfo.getFsmHandler().getStateData(fsmInfo.getName(), fsmExecution.getId(), state_info.id);
        FsmStateInputDataContextHelper fsch(input_data);

        QDBG_LOG("executing FSM state %y ID %y: %y", state_info.key, state_info.id, state_info.name);
        #! executed syncronously
        auto result = fsmInfo.getFsmHandler().executeFsm(state_info.name, input_data);
        QDBG_LOG("FSM %y result: %N", state_info.name, result);

        # set state result data
        fsmInfo.getFsmHandler().setStateData(fsmInfo.getName(), fsmExecution.getId(), state_info.id, result);
        last_result = result;
    }

    #! runs one given action
    private runOneStateAction(hash<auto> state_info, hash<auto> new_tld) {
        auto input_data = fsmInfo.getFsmHandler().getStateData(fsmInfo.getName(), fsmExecution.getId(), state_info.id);
        FsmStateInputDataContextHelper fsch(input_data);
        QDBG_LOG("runOneStateAction() (%y, %y, %y): input data: %y", fsmInfo.getName(), fsmExecution.getId(),
            state_info.id, input_data);

        auto result;
        # execute FSM state
        switch (state_info.action.type) {
            case "connector":
                result = callConnector(state_info, state_info.action.value, input_data);
                break;

            case "mapper":
                result = callMapper(state_info, state_info.action.value, input_data);
                break;

            case "pipeline":
                # pipelines don't have any output data
                callPipeline(state_info, state_info.action.value, input_data, new_tld);
                break;

            case "apicall":
                result = callApi(state_info, input_data);
                break;

            case "search-single":
                result = searchSingle(state_info, input_data);
                break;

            case "search":
                result = search(state_info, input_data);
                break;

            case "update":
                result = update(state_info, input_data);
                break;

            case "delete":
                result = deleteRecords(state_info, input_data);
                break;

            case "create":
                result = create(state_info, input_data);
                break;

            default:
                QDBG_ASSERT(False);
        }

        QDBG_LOG("FsmStrategy::runOneStateAction() result: %y", result);

        fsmInfo.getFsmHandler().setStateData(fsmInfo.getName(), fsmExecution.getId(), state_info.id, result);
        last_result = result;
    }

    # makes the given transition of the given state
    # checks whether the condition of a transition is satisfied and then updates the newStates
    # returns true if at least one transition was done
    private:internal bool makeStateTransitionInternal(hash<auto> state_info, auto state_data,
            hash<auto> transition) {
        QDBG_LOG("FsmStrategy::makeStateTransitionInternal() transition: %y", transition);
        bool result = False;
        if (transition.condition === "default") {
            # no condition
            result = True;
        } else if (transition.condition.typeCode() == NT_HASH) {
            # class connector
            QDBG_ASSERT(transition.condition.hasKey("class"));
            result = callConnector(state_info, transition.condition, state_data);
        } else {
            string label = fsmInfo.getName() + ":" + state_info.name + "->" + transition.state;
            result = evaluateExpression(state_info, transition.condition, transition.language, label, state_data);
        }

        QDBG_LOG("Condition result: %y", result);
        if (!result) {
            # here can be added logic, for example, to stay in the current state
            return False;
        }

        # make transition
        if (transition.hasKey("state")) {
            # locking not needed as qore operators are atomic by nature
            ++newStates{transition.state};

            hash<auto> trans_state_info = fsmInfo.getStateInfo(transition.state);

            fsmInfo.getFsmHandler().setStateData(fsmInfo.getName(), fsmExecution.getId(), trans_state_info.id,
                state_data);
            QDBG_LOG("transition is performed, added new state: %y ID %y", transition.state, trans_state_info.id);
        } else {
            QDBG_ASSERT(False);
        }

        return True;
    }

    # makes all state transitions in normal case
    private makeOneStateTransition(string state) {
        hash<auto> state_info = fsmInfo.getStateInfo(state);
        auto state_data = fsmInfo.getFsmHandler().getStateData(fsmInfo.getName(), fsmExecution.getId(),
            state_info.id);
        QDBG_LOG("FsmStrategy::makeOneStateTransition() state_data: %y", state_data);

        map makeStateTransitionInternal(state_info, state_data, $1), state_info.transitions;
    }

    # makes all state transitions in error case
    private makeOneStateErrorTransition(string state, hash<ExceptionInfo> ex) {
        hash<auto> state_info = fsmInfo.getStateInfo(state);
        UserApi::logError("FSM %y state %y exec ID %d error: %s: %s", fsmInfo.getName(), state_info.name,
            fsmExecution.getId(), ex.err, ex.desc);
        QDBG_LOG("FsmStrategy::makeOneStateErrorTransition() state: %s; ex: %s", state, get_exception_string(ex));

        bool handled = False;
        foreach hash<auto> transition in (state_info.transitions) {
            # if the thrown error is listed in the error list
            # can be improved to use patterns (regex) if needed
            if (transition.hasKey("errors") &&
                (inlist_hard("all", transition.errors) || inlist_hard(ex.err, transition.errors))) {
                if (makeStateTransitionInternal(state_info, ex, transition) && !handled) {
                    handled = True;
                }
            }
        }
        QDBG_LOG("FsmStrategy::makeOneStateErrorTransition() handled: %y", handled);
        if (!handled) {
            UserApi::logError("FSM %y state %y exec ID %d error not handled: %s", fsmInfo.getName(),
                state_info.name, fsmExecution.getId(), get_exception_string(ex));

            threadExceptionsMutex.lock();
            on_exit threadExceptionsMutex.unlock();

            if (!threadExceptionInfo) {
                threadExceptionInfo = ex;
            } else {
                reference<auto> rex = \threadExceptionInfo;
                while (rex.next) {
                    rex = \rex.next;
                }
                rex.next = ex;
            }
        }
    }
}

/**
    This strategy executes all actions of one of the current states and then makes its transitions
 */
class FsmOneStateStrategy inherits FsmStrategy {
    /**
        @param fsm_execution FsmExecution object
     */
    constructor(FsmExecution fsm_execution) : FsmStrategy(fsm_execution) {
        QDBG_LOG("creating FsmOneStateStrategy");
    }

    # overrides FsmStrategy method
    private concreteStrategy1(string current_state) {
        QDBG_LOG("Executing FsmOneStateStrategy, current_state: %y", current_state);
        makeOneStateTransition(current_state);
    }

    # overrides FsmStrategy method
    private concreteStrategy2(reference<hash<auto>> current_states, hash<auto> new_tld) {}
}

/**
    This strategy executes all actions of all current states and then makes their transitions
 */
class FsmAllStatesStrategy inherits FsmStrategy {
    /**
        @param fsm_execution FsmExecution object
    */
    constructor(FsmExecution fsm_execution) : FsmStrategy(fsm_execution) {
        QDBG_LOG("creating FsmAllStatesStrategy");
    }

    # overrides FsmStrategy method
    private concreteStrategy1(string current_state) {}

    # overrides FsmStrategy method
    private concreteStrategy2(reference<hash<auto>> current_states, hash<auto> new_tld) {
        QDBG_LOG("Executing FsmAllStatesStrategy");
        ThreadPool thread_pool(maxNumberOfThreads);
        foreach string current_state in (keys current_states) {
            string closure_current_state = current_state;
            thread_pool.submit(sub () {
                try {
                    ThreadLocalData::replace(new_tld);
                    makeOneStateTransition(closure_current_state);
                } catch (hash<ExceptionInfo> ex) {
                    makeOneStateErrorTransition(closure_current_state, ex);
                }
            });
        }
        thread_pool.stopWait();
    }
}

#! Sets and restores FSM state input data
class FsmStateInputDataContextHelper {
    private {
        auto old_input_data;
    }

    constructor(auto input) {
        old_input_data = tld.fsm_input_data;
        tld.fsm_input_data = input;
    }

    destructor() {
        tld.fsm_input_data = old_input_data;
    }
}
}
