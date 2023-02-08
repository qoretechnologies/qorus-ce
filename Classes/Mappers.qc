# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%push-parse-options
%new-style
%require-types
%strict-args

public namespace OMQ {
    #! A helper constant used in @ref QorusSqlStatementOutboundMapper_binding
    public const M_BIND = ("^bind^": True);
}

#! abstract class for a mapper provider; defines the interface for the class of object returned by the \c "get_mapper_providers()" function
public class OMQ::AbstractMapperType {
    # no public members
    public {}

    #! returns the name of the primary mapper class (must be unique in the mapper type list)
    abstract string getName();

    #! returns a hash of valid mapper options; the keys are the option names and the values are string descriptions for the options
    abstract hash<auto> getMapperOptions();

    #! returns a list of mapper options that must be given to create the input or output records for the mapper for mappers that can create either input records (ie requiresInput() is @ref False "False") and/or output records (ie requiresOutput() is @ref False "False"); these options must also be present in the getMapperOptions() output
    abstract *list<string> getRequiredRecordOptions();

    #! must return the Mapper object
    abstract Mapper::Mapper get(hash<auto> mapv, *hash<auto> opts);

    #! mapper definition must include the input record description; if this method returns @ref True "True", then the getInput() method must also be implemented for the subclass
    abstract bool requiresInput();

    #! mapper definition must include the output record description; if this method returns @ref True "True", then the getOutput() method must also be implemented for the subclass
    abstract bool requiresOutput();

    #! returns a hash of valid runtime mapper options; the keys are the option names and the values are string descriptions for the options
    *hash<auto> getRuntimeMapperOptions() {
    }

    #! returns user options; must be overridden in child classe to return a valid response
    hash<string, hash<MapperOptionInfo>> getMapperUserOptions() {
        return (map {
            $1.key: <MapperOptionInfo>{
                "type": "auto",
                "desc": $1.value,
            },
        }, getMapperOptions().pairIterator()) ?? {};
    }

    #! must return a iterator object given the input iterator that maps the input data to output in the iterator using the current Mapper
    Qore::AbstractIterator getIterator(Qore::AbstractIterator input, hash<auto> mapv, *hash<auto> opts) {
        return new MapperIterator(input, get(mapv, opts));
    }

    #! returns a list of mapper options that must be given to create the mapper (these options must also be present in the getMapperOptions() output); by default this method returns getRequiredRecordOptions() + \c "input" (if requiresInput() returns @ref False "False") + \c "output" (if requiresOutput() returns @ref False "False")
    *list<string> getRequiredOptions() {
        *list<softstring> l = getRequiredRecordOptions();
        if (!requiresInput())
            l += ("input",);
        if (!requiresOutput())
            l += ("output",);
        return l;
    }

    #! returns a hash of configuration info for the mapper type
    hash<auto> getConfigInfo() {
        return {
            "name": getName(),
            "options": getMapperOptions(),
            "user_options": getMapperUserOptions(),
            "runtime_options": getRuntimeMapperOptions(),
            "required_options": getRequiredOptions(),
            "required_record_options": getRequiredRecordOptions(),
            "requires_input": requiresInput(),
            "requires_output": requiresOutput(),
        };
    }

    #! called for mapper providers that automatically define the input record
    hash<auto> getInput(string mname, hash<auto> opth) {
        return opth.input ?? {};
    }

    #! called for mapper providers that automatically define the output record
    hash<auto> getOutput(string mname, hash<auto> opth) {
        return opth.output ?? {};
    }

    #! whether the mapper is valid, i.e. eligible for parsing and other "regular" actions
    bool isValid() {
        return True;
    }
}

#! system mapper class for prividing @ref Mapper::Mapper objects at runtime
/** This mapper type does not require any special options, but also does not provide default values for any @ref mapper_options "options", therefore the @ref mapper_input "input" and mapper-options-output "output" options must be explicitly defined (requiresInput() and requiresOutput() both return @ref True)

    Example:
    @code{.py}
# name: my-example-mapper
# version: 1.0
# desc: Example mapper for documentation
# type: Mapper
# author: Joesephine Programmer (Qore Technologies, s.r.o.)
# functions: my-mapper-lib
# parse-options: PO_NEW_STYLE
# define-group: Example: Example interface objects
# groups: Example

OPTION: input: (
    "order_id": "unique order ID",
    #...
)
OPTION: output: (
    "order_number": (
        "type": "number",
        "desc": "the unique order number for the order",
    ),
    # ...
)
    @endcode
*/
public class OMQ::MapperType inherits OMQ::AbstractMapperType {
    public {
        #! List of runtime options for generic mappers
        const MapperRuntimeOptionList = (
            "input_provider_search",
            "input_request",
            "input_request_options",
            "input_search_options",
            "output_provider_bulk",
            "output_provider_upsert",
            "output_request_options",
        );

        #! Runtime options for generic mappers
        const MapperRuntimeOptions = map {$1.key: $1.value.desc},
            Mapper::UserOptions{MapperRuntimeOptionList}.pairIterator();
    }

    #! returns \c "Mapper", the name of the primary mapper class (must be unique in the mapper type list)
    string getName() {
        return "Mapper";
    }

    #! mapper definition must include the input record description
    bool requiresInput() {
        return True;
    }

    #! mapper definition must include the output record description
    bool requiresOutput() {
        return True;
    }

    #! returns a hash of valid runtime mapper options; the keys are the option names and the values are string descriptions for the options
    *hash<auto> getRuntimeMapperOptions() {
        return MapperRuntimeOptions;
    }

    #! returns a hash of valid mapper options; the keys are the option names and the values are string descriptions for the options
    hash<auto> getMapperOptions() {
        return QorusMapper::OptionKeys;
    }

    #! returns user options
    hash<string, hash<MapperOptionInfo>> getMapperUserOptions() {
        return QorusMapper::UserOptions;
    }

    #! returns a list of mapper options that must be given to create the input or output records for the mapper for mappers that can create either input records (ie requiresInput() is @ref False "False") and/or output records (ie requiresOutput() is @ref False "False"); these options must also be present in the getMapperOptions() output
    *list<string> getRequiredRecordOptions() {
    }

    #! returns a @ref Mapper::Mapper object
    Mapper::Mapper get(hash<auto> mapv, *hash<auto> opts) {
        return new QorusMapper(mapv, opts);
    }
}

#! this class provides a plain mapper based on @ref Mapper::Mapper with consistent constructor arguments
public class OMQ::QorusMapper inherits Mapper::Mapper {
    #! create the object based on the option arguments
    /** @param mapv the mapper description; see @ref mapperkeys for more info
        @param opts see @ref mapperoptions for more info

        @throw MAP-ERROR the map hash has a logical error (ex: 'trunc' key given without 'maxlen', invalid map key)
    */
    constructor(hash<auto> mapv, *hash<auto> opts) : Mapper(mapv, QorusMapper::getOptions(opts)) {
    }

    #! called in the constructor to get the @ref SqlUtil::Table "Table" object
    static hash<auto> getOptions(hash<auto> opts) {
%ifdef QorusServer
        string name = opts.name;
        # set logging options for server
        if (!opts.input_log)
            opts.input_log = sub (hash<auto> h) { UserApi::logDebug("mapper %y input: %y", name, h); };
        if (!opts.output_log)
            opts.output_log = sub (hash<auto> h) { UserApi::logDebug("mapper %y output: %y", name, h); };
        if (!opts.info_log)
            opts.info_log = sub (string fmt) { UserApi::logInfo("mapper %y info: %s", name, vsprintf(fmt, argv)); };
%endif
        return opts;
    }
}

#! system mapper class for prividing @ref TableMapper::InboundTableMapper objects at runtime
/** requires the following @ref mapper_options "mapper options":
    - \c "datasource": a string giving the @ref dsconn "Qorus datasource" name for the target table
    - \c "table": a string giving the target table name in the @ref dsconn "datasource"

    The @ref mapper_input "input" option is required, but this class automatically provides a definition for the
    @ref mapper_output "output" option based on the target table description, so no @ref mapper_output "output" option
    should be given with mappers of this type

    Example:
    @code{.py}
# name: my-example-table-mapper
# version: 1.0
# desc: Example table mapper for documentation
# type: InboundTableMapper
# author: Joesephine Programmer (Qore Technologies, s.r.o.)
# functions: my-mapper-lib
# parse-options: PO_NEW_STYLE
# define-group: Example: Example interface objects
# groups: Example

OPTION: datasource: "omquser"
OPTION: table: "example_table"
OPTION: input: (
    "order_id": "unique order ID",
    #...
    )
    @endcode

    */
public class OMQ::InboundTableMapperType inherits OMQ::AbstractMapperType {
    #! returns \c "InboundTableMapper", the name of the primary mapper class (must be unique in the mapper type list)
    string getName() {
        return "InboundTableMapper";
    }

    #! mapper definition must include the input record description
    bool requiresInput() {
        return True;
    }

    #! mapper definition does not have to include the output record description; the output record description is provided by the table
    bool requiresOutput() {
        return False;
    }

    #! returns a hash of valid mapper options; the keys are the option names and the values are string descriptions for the options
    hash<auto> getMapperOptions() {
        return OMQ::QorusInboundTableMapper::OptionKeys;
    }

    #! returns user options
    hash<string, hash<MapperOptionInfo>> getMapperUserOptions() {
        return OMQ::QorusInboundTableMapper::UserOptions;
    }

    #! returns a list of mapper options that must be given to create the input or output records for the mapper for mappers that can create either input records (ie requiresInput() is @ref False "False") and/or output records (ie requiresOutput() is @ref False "False"); these options must also be present in the getMapperOptions() output
    *list<string> getRequiredRecordOptions() {
        return ("datasource", "table");
    }

    #! returns a @ref TableMapper::InboundTableMapper object
    Mapper::Mapper get(hash<auto> mapv, *hash<auto> opts) {
        return new QorusInboundTableMapper(mapv, opts);
    }

    #! must return a iterator object given the input iterator that maps the input data to output in the iterator using the current Mapper
    Qore::AbstractIterator getIterator(Qore::AbstractIterator input, hash<auto> mapv, *hash<auto> opts) {
        return new QorusInboundTableMapperIterator(input, mapv, opts);
    }

    #! returns the output record from the table
    *hash<string, AbstractDataField> getOutput(string mname, hash<auto> opth) {
        AbstractTable table = UserApi::getSqlTable(opth.datasource, opth.table);
        return InboundTableMapper::getOutputRecord(mname, table, opth);
    }
}

#! this class provides an inbound table mapper based on @ref TableMapper::InboundTableMapper with consistent constructor arguments
public class OMQ::QorusInboundTableMapper inherits TableMapper::InboundTableMapper {
    public {
        #! valid mapper keys
        const OptionKeys = TableMapper::InboundTableMapper::OptionKeys
            + (map {$1.key: $1.value.desc}, UserOptions.pairIterator());

        #! valid user options
        const UserOptions = {
            "datasource": <MapperOptionInfo>{
                "type": "string",
                "desc": "(required) the name of the Qorus datasource containing the target table",
            },
            "table":  <MapperOptionInfo>{
                "type": "string",
                "desc": "(required) the name of the table or updateable view for the mapper object",
            },
        };
    }

    #! create the object based on the option arguments
    /** @param mapv the mapper description; see @ref mapperkeys for more info
        @param opts see @ref mapperoptions for more info; the following additional keys are required for this class:
        - \c "datasource": the name of the @ref dsconn "Qorus datasource"
        - \c "table": the name of the target table for inserting

        @throw MAP-ERROR the map hash has a logical error (ex: 'trunc' key given without 'maxlen', invalid map key)
        @throw UNKNOWN-COLUMN field name not recognized
        @throw MISSING-COLUMN map is missing a mapping for a column with a NOT NULL constraint

        @note other exceptions can be thrown by @ref sqlutilintro "SqlUtil" in case of errors acquiring the @ref SqlUtil::Table "Table"
    */
    constructor(hash<auto> mapv, *hash<auto> opts) : InboundTableMapper(QorusInboundTableMapper::getTable(\opts), mapv, opts) {
    }

    #! called in the constructor to get the @ref SqlUtil::Table "Table" object
    static SqlUtil::AbstractTable getTable(reference opts) {
        *string ds = remove opts.datasource;
        if (!ds)
            throw "MAP-ERROR", "missing \"datasource\" InboundTableMapper option giving the datasource for the table";
        *string table = remove opts.table;
        if (!table)
            throw "MAP-ERROR", sprintf("missing \"table\" InboundTableMapper option giving the target table name in datasource %y", ds);
        if (table.typeCode() != NT_STRING)
            throw "MAP-ERROR", sprintf("\"table\" InboundTableMapper option for datasource %y should be type \"string\" got type %y instead", ds, table.type());

%ifdef QorusServer
        # set logging options for server
        if (!opts.input_log)
            opts.input_log = sub (hash<auto> h) { qlog(LoggerLevel::DEBUG, "%s input: %y", table, h); };
        if (!opts.output_log)
            opts.output_log = sub (hash<auto> h) { qlog(LoggerLevel::DEBUG, "%s output: %y", table, h); };
        if (!opts.info_log)
            opts.info_log = sub (string fmt) { qlog(LoggerLevel::INFO, "%s info: %s", table, vsprintf(fmt, argv)); };

        return UserApi::getSqlTable(ds, table);
%else
        return new Table(omqclient.getDatasource(ds), table).getTable();
%endif
    }
}

#! this class provides an inbound table mapper iterator based on @ref TableMapper::InboundTableMapperIterator with consistent constructor arguments
public class OMQ::QorusInboundTableMapperIterator inherits TableMapper::InboundTableMapperIterator {
    #! creates the iterator from the arguments passed
    /** @param input input iterator; @ref Qore::AbstractIterator::getValue() "AbstractIterator::getValue()" must return a hash
        @param mapv a hash providing field mappings; each hash key is the name of the output column in lower case in the target table; each value is either @ref True "True" (meaning no translations are done; the data is copied 1:1) or a hash describing the mapping; see @ref mapperkeys for detailed documnentation for this option
        @param opts an optional hash of options for the mapper; see @ref mapperoptions for a description of valid mapper options; the following additional keys are required for this class:
        - \c "datasource": the name of the @ref dsconn "Qorus datasource"
        - \c "table": the name of the target table for inserting

        @see TableMapper::InboundTableMapperIterator::constructor() for more information
    */
    constructor(Qore::AbstractIterator input, hash<auto> mapv, *hash<auto> opts) : InboundTableMapperIterator(input, QorusInboundTableMapper::getTable(\opts), mapv, opts) {
    }
}

#! system mapper class for prividing @ref OMQ::QorusSqlStatementOutboundMapper objects at runtime
public class OMQ::QorusSqlStatementOutboundMapperType inherits OMQ::AbstractMapperType {
    #! returns \c "QorusSqlStatementOutboundMapper", the name of the primary mapper class (must be unique in the mapper type list)
    string getName() {
        return "QorusSqlStatementOutboundMapper";
    }

    #! mapper definition does not include the input record description; it is taken from the DB
    bool requiresInput() {
        return False;
    }

    #! mapper definition does have to include the output record description
    bool requiresOutput() {
        return True;
    }

    #! returns a list of mapper options that must be given to create the input or output records for the mapper for mappers that can create either input records (ie requiresInput() is @ref False "False") and/or output records (ie requiresOutput() is @ref False "False"); these options must also be present in the getMapperOptions() output
    *list<string> getRequiredRecordOptions() {
        return ("datasource", "table",);
    }

    #! returns a hash of valid mapper options; the keys are the option names and the values are string descriptions for the options
    hash<auto> getMapperOptions() {
        return OMQ::QorusSqlStatementOutboundMapper::OptionKeys;
    }

    #! returns user options
    hash<string, hash<MapperOptionInfo>> getMapperUserOptions() {
        return OMQ::QorusSqlStatementOutboundMapper::UserOptions;
    }

    #! returns a hash of valid runtime mapper options; the keys are the option names and the values are string descriptions for the options
    *hash<auto> getRuntimeMapperOptions() {
        return {
            "bind": "Bind values to the where condition",
        };
    }

    #! returns the input record as defined by the select criteria
    /** cannot use "hash<auto>" for "opth"; must strip types here
    */
    *hash<string, AbstractDataField> getInput(string mname, hash opth) {
        # provide NULL values for runtime parameters
        HashIterator it(opth.sh."where");
        while (it.next()) {
            auto v = it.getValue();
            if (v.typeCode() == NT_HASH && v.hasKey("^bind^"))
                opth.sh."where".(it.getKey()) = NULL;
        }
        return SqlStatementOutboundMapper::getStaticInputRecord(UserApi::getSqlTable(opth.datasource, opth.table), opth.sh, NOTHING, opth.input);
    }

    #! returns a @ref TableMapper::InboundTableMapper object
    Mapper::Mapper get(hash mapv, *hash opts) {
        return new QorusSqlStatementOutboundMapper(mapv, opts);
    }

    #! must return a iterator object given the input iterator that maps the input data to output in the iterator using the current Mapper
    Qore::AbstractIterator getIterator(Qore::AbstractIterator input, hash mapv, *hash opts) {
        return new MapperIterator(input, mapv, opts);
    }

    static hash<auto> combineHash(hash<auto> ih, *hash<auto> h) {
        # combine (but do not overwrite) any attributes of the given input hash with the one from the DB, but combine "desc" keys
        foreach hash<auto> kh in (h.pairIterator()) {
            # ignore unknown keys and input values not in hash format
            if (!ih{kh.key} || kh.value.typeCode() != NT_HASH)
                continue;
            foreach hash<auto> vh in (kh.value.pairIterator()) {
                if (!ih{kh.key}.hasKey(vh.key))
                    ih{kh.key}{vh.key} = vh.value;
                else if (vh.key == "desc") {
                    ih{kh.key}.desc += "; " + vh.value;
                }
            }
        }
        return ih;
    }
}

#! Qorus oubound mapper based on SqlUtil select
/**

    Options used for QorusSqlStatementOutboundMapper are:
        - \c datasource: (required) the name of the @ref dsconn "Qorus datasource" containing the target table
        - \c table: (required) the name of the leading table or view for the select hash
        - \c sh: (optional) an SqlUtil select hash for the \c table. It can use @ref QorusSqlStatementOutboundMapper_binding

    Example of the mapper definition in the qmapper file:
    @code{.py}
# name: regression-out-sql-statement
# version: 1.0
# desc: Regression test for QorusSqlStatementOutboundMapper
# type: QorusSqlStatementOutboundMapper
# author: Petr Vanek (Qore Technologies, s.r.o.)

OPTION: datasource: "omquser"
OPTION: table:      "regression_example"
OPTION: sh: {
    "columns": "uuid",
    "where": {
        "in_transit": M_BIND,
        "qorus_wfiid": {
            "^bind^":"parent_wfiid"
        },
    },
}
OPTION: output: (
)

FIELD: "uuid_mapped": "uuid"
FIELD: "some_const": ("constant" : "foobar")
# END
    @endcode

    @section QorusSqlStatementOutboundMapper_binding QorusSqlStatementOutboundMapper Variable Binding

    When QorusSqlStatementOutboundMapper is initialized it can get the \c bind runtime option
    to make \c sh parametrized at runtime.

    Example of mapper initialization in the workflow step:
    @code{.py}
hash<auto> ropts = {
    "bind": {
        "in_transit": 5,
        "parent_wfiid": 1000,
    },
};
QorusSqlStatementOutboundMapper m = getMapper("regression-out-sql-statement", ropts);
    @endcode

    Then values provided in runtime options (\c ropts), key \c "bind" are passed to the
    mappers's select hash.

    You can se use of the so called variable binding in the example above.
    - OMQ::M_BIND is a helper constant which says to the runtime that bound hash will contain
      the same key as the where condition hash key.
    - {"^bind^": \c string} says that where condition hash key will be bound by
      the value of \c string in the binding hash
 */
public class OMQ::QorusSqlStatementOutboundMapper inherits TableMapper::SqlStatementOutboundMapper {
    public {
        #! valid mapper keys
        const OptionKeys = TableMapper::SqlStatementOutboundMapper::OptionKeys
            + (map {$1.key: $1.value.desc}, UserOptions.pairIterator());

        #! valid user options
        const UserOptions = QorusInboundTableMapper::UserOptions + {
            "sh": <MapperOptionInfo>{
                "type": "hash",
                "desc": "(optional) an SqlUtil select hash",
            },
            "bind": <MapperOptionInfo>{
                "type": "hash",
                "desc": "(optional) a runtime bind-variable hash",
            },
        };
    }

    #! constructs a mapper object
    /** @param mapv a mapping hash
        @param opts a option hash
     */
    constructor(hash<auto> mapv, *hash<auto> opts)
        : SqlStatementOutboundMapper(QorusSqlStatementOutboundMapper::getTable(\opts),
                                     QorusSqlStatementOutboundMapper::getSelectHash(\opts),
                                     mapv,
                                     opts
                                    ) {
    }

    #! initializes the internal statement object
    private initOptions(reference<*hash<auto>> opts) {
        # tansform binding option hash in the SqlStatementOutboundMapper
        *hash<auto> binding = remove opts.bind;
        if (binding && opts.sh) {
            HashIterator it(opts.sh."where");
            while (it.next()) {
                auto v = it.getValue();
                if (v.typeCode() == NT_HASH && v.hasKey("^bind^")) {
                    softstring runtimeKey;
                    switch (v."^bind^".typeCode()) {
                        case NT_BOOLEAN:
                            runtimeKey = it.getKey();
                            break;
                        case NT_STRING:
                            runtimeKey = v."^bind^";
                            break;
                        default:
                            throw "QORUS-SQL-STATEMENT-OUTBOUND-MAPPER-ERROR", sprintf("Binding error: bound value is not of type hash with '^bind^' key: %s", v."^bind^".type());
                    }
                    if (!binding.hasKey(runtimeKey))
                        throw "QORUS-SQL-STATEMENT-OUTBOUND-MAPPER-ERROR", sprintf("Binding error: bound runtime options do not contain key '%s'", runtimeKey);
                    opts.sh."where"{it.getKey()} = binding{runtimeKey};
                }
            }
        }

        SqlStatementOutboundMapper::initOptions(\opts);
    }

    #! returns a list of valid constructor options for this class (can be overridden in subclasses)
    /** @return a list of valid constructor options for this class (can be overridden in subclasses)
    */
    hash<auto> optionKeys() {
        return OptionKeys;
    }

    #! called in the constructor to get the @ref SqlUtil::Table "Table" object
    static SqlUtil::AbstractTable getTable(reference<*hash<auto>> opts) {
        *string ds = remove opts.datasource;
        if (!ds)
            throw "MAP-ERROR", "missing \"datasource\" SqlStatementOutboundMapper option giving the datasource for the table";
        *string table = remove opts.table;
        if (!table)
            throw "MAP-ERROR", sprintf("missing \"table\" SqlStatementOutboundMapper option giving the target table name in datasource %y", ds);
        if (table.typeCode() != NT_STRING)
            throw "MAP-ERROR", sprintf("\"table\" SqlStatementOutboundMapper option for datasource %y should be type \"string\" got type %y instead", ds, table.type());

%ifdef QorusServer
        # set logging options for server
        if (!opts.input_log)
            opts.input_log = sub (hash<auto> h) { qlog(LoggerLevel::DEBUG, "%s input: %y", table, h); };
        if (!opts.output_log)
            opts.output_log = sub (hash<auto> h) { qlog(LoggerLevel::DEBUG, "%s output: %y", table, h); };
        if (!opts.info_log)
            opts.info_log = sub (string fmt) { qlog(LoggerLevel::INFO, "%s info: %s", table, vsprintf(fmt, argv)); };

        return UserApi::getSqlTable(ds, table);
%else
        return new Table(omqclient.getDatasource(ds), table).getTable();
%endif
    }

    #! called in the constructor to get the SqlUtil select hash from options
    static *hash<auto> getSelectHash(reference<*hash<auto>> opts) {
        return remove opts.sh;
    }

} # SqlStatementOutboundMapper

#! defines the mapper type for raw outbound SQL mappers
public class OMQ::QorusRawSqlStatementOutboundMapperType inherits OMQ::AbstractMapperType {
    #! returns \c "SqlStatementOutboundMapper", the name of the primary mapper class (must be unique in the mapper type list)
    string getName() {
        return "QorusRawSqlStatementOutboundMapper";
    }

    #! mapper definition does not include the input record description; all is taken from the DB
    bool requiresInput() {
        return False;
    }

    #! mapper definition does have to include the output record description
    bool requiresOutput() {
        return True;
    }

    #! returns a list of mapper options that must be given to create the input or output records for the mapper for mappers that can create either input records (ie requiresInput() is @ref False "False") and/or output records (ie requiresOutput() is @ref False "False"); these options must also be present in the getMapperOptions() output
    *list<string> getRequiredRecordOptions() {
        return ("datasource", "select",);
    }

    #! returns a hash of valid mapper options; the keys are the option names and the values are string descriptions for the options
    hash<auto> getMapperOptions() {
        return OMQ::QorusRawSqlStatementOutboundMapper::OptionKeys;
    }

    #! returns user options
    hash<string, hash<MapperOptionInfo>> getMapperUserOptions() {
        return OMQ::QorusRawSqlStatementOutboundMapper::UserOptions;
    }

    #! returns a hash of valid runtime mapper options; the keys are the option names and the values are string descriptions for the options
    *hash<auto> getRuntimeMapperOptions() {
        return {
            "bind": "Bind values for the where condition",
        };
    }

    #! returns the input record as defined by the select criteria
    *hash<string, AbstractDataField> getInput(string mname, hash<auto> opth) {
        return RawSqlStatementOutboundMapper::getStaticInputRecord(UserApi::getDatasourcePool(opth.datasource),
            opth."select", NOTHING, opth.input);
    }

    #! returns a @ref TableMapper::InboundTableMapper object
    Mapper::Mapper get(hash<auto> mapv, *hash<auto> opts) {
        return new QorusRawSqlStatementOutboundMapper(mapv, opts);
    }

    #! must return a iterator object given the input iterator that maps the input data to output in the iterator using the current Mapper
    Qore::AbstractIterator getIterator(Qore::AbstractIterator input, hash<auto> mapv, *hash<auto> opts) {
        return new MapperIterator(input, mapv, opts);
    }
}

#! Qorus oubound mapper based on raw SQL select statement
/**
    Options used for SqlRawStatementOutboundMapper are:
        - \c datasource: (required) the name of the @ref dsconn "Qorus datasource" containing the target table
        - \c select: (required) the name of the leading table or view for the select hash
        - \c bind: (optional) an SqlUtil select hash for the \c table. It can use @ref QorusSqlStatementOutboundMapper_binding

    Example of the mapper definition in the qmapper file:
    @code{.py}
# name: regression-out-sql-statement
# version: 1.0
# desc: Regression test for QorusSqlStatementOutboundMapper
# type: QorusRawSqlStatementOutboundMapper
# author: Petr Vanek (Qore Technologies, s.r.o.)

OPTION: datasource: "omquser"
OPTION: select: "select * from my_table where id = %v"
OPTION: output: ()

FIELD: "uuid_mapped"        : "uuid"
FIELD: "some_const"         : ("constant" : "foobar")
# END
    @endcode

    @section SqlRawStatementOutboundMapper_binding SqlRawStatementOutboundMapper Variable Binding

    When SqlRawStatementOutboundMapper is initialized it can get the \c bind runtime option
    to make \c sh parametrized at runtime.

    Example of mapper initialization in the workflow step:
    @code{.py}
hash<auto> ropts = {"bind": 1};
SqlRawStatementOutboundMapper m = get_mapper("regression-out-sql-statement", ropts);
    @endcode

    Then values provided in runtime options (\c ropts), key \c "bind" are passed to the
    mappers's select statement. Resulting in for example:

    @code{.sql}
select * from my_table where id = :var_1;
-- binding 1 into :var_1
    @endcode
 */
public class OMQ::QorusRawSqlStatementOutboundMapper inherits TableMapper::RawSqlStatementOutboundMapper {
    public {
        #! valid mapper keys
        const OptionKeys = TableMapper::RawSqlStatementOutboundMapper::OptionKeys
            + (map {$1.key: $1.value.desc}, UserOptions.pairIterator());

        #! valid user options
        const UserOptions = (map {
                $1.key: <MapperOptionInfo>{
                    "type": "auto",
                    "desc": $1.value,
                },
            }, QorusSqlStatementOutboundMapper::UserOptions.pairIterator()
            - ("table", "sh")) + {
            "select": <MapperOptionInfo>{
                "type": "string",
                "desc": "(required) the SQL statement to use",
            },
            "bind": <MapperOptionInfo>{
                "type": "list",
                "desc": "(optional) a runtime bind-variable list for bind parameters in the select statement",
            },
        };
    }

    #! constructs a mapper object
    /** @param mapv a mapping hash
        @param opts a option hash
     */
    constructor(hash<auto> mapv, *hash<auto> opts)
        : RawSqlStatementOutboundMapper(QorusRawSqlStatementOutboundMapper::getDatasource(\opts),
                                        remove opts."select",
                                        remove opts."bind",
                                        mapv,
                                        opts
                                       ) {
    }

    #! called in the constructor to get the @ref SqlUtil::Table "Table" object
    static Qore::SQL::AbstractDatasource getDatasource(reference<*hash<auto>> opts) {
%ifdef QorusServer
        # set logging options for server
        if (!opts.input_log)
            opts.input_log = sub (hash<auto> h) { qlog(LoggerLevel::DEBUG, "sql input: %y", h); };
        if (!opts.output_log)
            opts.output_log = sub (hash<auto> h) { qlog(LoggerLevel::DEBUG, "sq output: %y", h); };
        if (!opts.info_log)
            opts.info_log = sub (string fmt) { qlog(LoggerLevel::INFO, "sql info: %s", vsprintf(fmt, argv)); };
%endif
        return UserApi::getDatasourcePool(remove opts.datasource);
    }

    #! returns a list of valid constructor options for this class (can be overridden in subclasses)
    /** @return a list of valid constructor options for this class (can be overridden in subclasses)
    */
    hash<auto> optionKeys() {
        return OptionKeys;
    }

} # QorusRawSqlStatementOutboundMapper

public class MapperContainerBase {
    public {
        int mapperid;
        string name;
        string version;
        *string patch;
        *string desc;
        date created;
        date modified;

        # source for mapper options
        *hash<auto> option_source;

        # source for mapper fields
        hash<auto> field_source;

        #! cannot be "hash<auto>"; we need to strip types here
        hash fields;

        #! list of parse options
        *list<auto> parse_options;

        #! "no exception" flag; do not throw an exception if an error is raised
        *bool no_exception;
    }

    private {
        AbstractMapperType mtype;

        # container Program for executable mapper source
        MapperProgram p;
    }

    constructor(softint mid, string n, string v, *string pt, *string d, AbstractMapperType m, *string parse_option_str,
            string fields_, *string options_, *hash<auto> props, date n_created, date n_modified, bool is_yaml,
            *bool no_exception) {
        if (no_exception) {
            self.no_exception = True;
        }
        # process parse options
        int po = 0;
        if (parse_option_str) {
            parse_options = parse_option_str.split(",");
            trim parse_options;
            foreach string opt in (parse_options) {
                *int c = ParseOptionStringMap{opt};
                if (!c) {
                    error("cannot process unknown parse option %y", opt);
                }
                if (!(c & MapperParseOptionMask)) {
                    error("mapper configuration references illegal parse option %y; valid parse options: %y", opt,
                        (map ParseOptionCodeMap.$1, MapperParseOptionList));
                }
                po |= c;
            }
        }

        mapperid = mid;
        name = n;
        version = v;
        patch = pt;
        desc = d;
        created = n_created;
        modified = n_modified;
        mtype = m;
        p = setupProgram(po, props);
%ifdef QorusServer
        p.setProgramName(mapperid, name, version);
%endif

        if (is_yaml) {
            field_source = deserialize_qorus_data(fields_);
            fields = field_source;
            map field_source{$1.key} = Qorize::qorize_val($1.value), field_source.pairIterator();
            prepareSourceFields();
            parsePending(field_source, po, props, "FIELD", "fields");
        } else {
            try {
                *hash<auto> th = parseHashExpression(po, props, fields_, "FIELD", \processFieldValue());
                if (!th) {
                    throw "MISSING-FIELDS", "field definition is empty";
                }
                field_source = th;
            } catch (hash<ExceptionInfo> ex) {
                error("failed to parse field source: %s: %s", ex.err, ex.desc);
            }
        }

        if (is_yaml && options_) {
            option_source = deserialize_qorus_data(options_);
            prepareOptionsYaml();
            parsePending(option_source, po, props, "OPTION", "options");
        } else if (options_) {
            try {
                option_source = parseHashExpression(po, props, options_, "OPTION");
            } catch (hash<ExceptionInfo> ex) {
                error("failed to parse options: %s: %s", ex.err, ex.desc);
            }
        }

        try {
            parseCommitImpl();
        } catch (hash<ExceptionInfo> ex) {
            error("failed to parse mapper: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
        }
    }

    private:internal *string removeEscapeQuotes(string code_) {
        return (code_ =~ s/\"(auto sub \(auto ctx, auto record\) { return [a-zA-Z_{1}][a-zA-Z0-9_]+\(ctx, record\); })\",/$1/);
    }

    private:internal prepareSourceFields() {
        foreach string key in (keys fields) {
            if (fields{key}.typeCode() == NT_HASH && fields{key}.hasKey("code") &&
                fields{key}{"code"}.typeCode() == NT_STRING) {
                field_source{key} = removeEscapeQuotes(field_source{key});
            }
        }
    }

    private:internal prepareOptionsYaml() {
        hash<auto> dont_qorize_keys = {};

        # change option: code: some_function() to
        # option: some_function()
        foreach auto iterator in (option_source.pairIterator()) {
            if (iterator.value.typeCode() == NT_HASH && iterator.value.hasKey("code")) {
                option_source{iterator.key} = option_source{iterator.key}{"code"};
                dont_qorize_keys{iterator.key} = True;
            }
        }

        # do the same for runtime options
        if (option_source.hasKey("runtime") && option_source{"runtime"}.typeCode() == NT_HASH) {
            foreach auto iterator in (option_source{"runtime"}.pairIterator()) {
                if (iterator.value.typeCode() == NT_HASH && iterator.value.hasKey("code")) {
                    option_source{"runtime"}{iterator.key} = option_source{"runtime"}{iterator.key}{"code"};
                }
            }
        }

        foreach hash<auto> iterator in (option_source.pairIterator()) {
            if (dont_qorize_keys.hasKey(iterator.key)) {
                continue;
            }
            option_source{iterator.key} = Qorize::qorize_val(iterator.value);

            if (iterator.key == "runtime") {
                # hacky - convert string to a function call
                # example: "systemDate()" to systemDate()
                option_source{iterator.key} = replace(option_source{iterator.key}, ")\"", ")");
                option_source{iterator.key} = replace(option_source{iterator.key}, ": \"", ": ");
            }
        }
    }

    private MapperProgram setupProgram(int po, *hash<auto> props) {
        MapperProgram p = setupProgramImpl(po, props);
        try {
            loadLibraryImpl(p);
        } catch (hash<ExceptionInfo> ex) {
            error("failed to load library: %s: %s", ex.err, ex.desc);
        }
        return p;
    }

    private MapperProgram setupProgramImpl(int po, *hash<auto> props) {
        return new MapperProgram(po, qorus_get_system_options(), props);
    }

    private hash<auto> exec(string attname) {
        string fn = sprintf("__mapper_sys_get_%s", attname);
        try {
            auto th = p.callFunction(fn);
            if (th.typeCode() != NT_HASH)
                throw "ERROR", sprintf("%s attribute should return \"hash\" but got type %y instead", attname,
                    th.type());
            return th;
        } catch (hash<ExceptionInfo> ex) {
            throw "ERROR", sprintf("failed to execute source for %s attribute: %s: %s: %s", attname, get_ex_pos(ex),
                ex.err, ex.desc);
        }
    }

    # parses a string to ensure it is a hash with string value keys
    private *hash<auto> parseHashExpression(int po, *hash<auto> props, string str, string vtype, *code processValue) {
        string vname = vtype.lwr() + "s";

        DataLineIterator i(str);

        hash<auto> rv;

        string key;
        string value;
        string re = sprintf("^%s:(.*)\$", vtype);

        code finalize = sub () {
            if (!key)
                return;

            trim value;
            if (processValue)
                processValue(key, \value);
            rv{key} = value;
            delete key;
            delete value;
        };

        while (i.next()) {
            string line = i.getValue();

            if ((*string v = regex_extract(line, re)[0])) {
                (*string k, *string val) = (v =~ x/([^:]+):(.+)$/);
                trim k;
                # remove quotes on key
                if (k =~ /^(".*"|'.*')$/)
                    k =~ s/^.(.*).$/$1/;

                if (!k || !val)
                    error("%s line %d: malformed declaration: not in <key>: <value> format", vname, i.index());
                if (rv{k})
                    error("%s line %d: key %y repeated on line %d", vname, i.index(), k);

                finalize();
                key = k;
                value = val;
                continue;
            }

            if (value) {
                value += "\n" + line;
                continue;
            }

            if (line =~ /^\s?#/ || line =~ /^\s*$/) {
                continue;
            }

            error("cannot parse %s line %d in mapper %s v%s: %y...", vtype, i.index(), name, version, line.substr(0, 20));
        }
        finalize();

        parsePending(rv, po, props, vtype, vname);
        return rv;
    }

    private parsePending(hash<auto> rv, int po, *hash<auto> props, string vtype, string vname) {
        if (!rv) {
            return;
        }
        string hsrc = foldl $1 + "\n," + $2, (map sprintf("%y: %s", $1.key, $1.value), rv.pairIterator());
        string fn = sprintf("__mapper_sys_get_%s", vname);
        string label = sprintf("mapper %s v%s %s", name, version, vname);
        try {
            p.parsePending("auto sub " + fn + "() {return {" + hsrc + "\n};}", "<" + label + ">");
        } catch (hash<ExceptionInfo> ex) {
            # output a user-friendly error with the key info that fails
            bool err;
            foreach hash<auto> h in (rv.pairIterator()) {
                MapperProgram tp = setupProgram(po, props);
                string ksrc = sprintf("%y: %y", h.key, h.value);
                try {
                    string src = sprintf("auto sub t_%s_%d() { return (%s\n);}", vname, $#, ksrc);
                    tp.parse(src, sprintf("<%s key: %y>", label, h.key));
                } catch (hash<ExceptionInfo> nex) {
                    error("cannot parse %s key %y: %s: %s: source: %y", vtype, h.key, nex.err, nex.desc, ksrc);
                    err = True;
                }
            }
            # should not happen - but in case parsing succeeds with all keys, then we raise a generic error
            if (!err)
                error("cannot parse %s: %s: %s: source: %s", vtype, ex.err, ex.desc, hsrc);
        }
    }

    private processFieldValue(string key, reference<string> val) {
        # process "True" to a 1:1 input -> output mapping
        if (val == "True") {
            val = sprintf("{\"name\": \"%s\"}", key);
            return;
        }
        # process simple input field name to a hash
        *string fn = (val =~ x/^"(.+)"$/)[0];
        if (fn) {
            val = sprintf("{\"name\": \"%s\"\n}", fn);
            return;
        }
        # process naked closures to a hash
        if (val =~ /^([A-Za-z][A-Za-z0-9_]*)?sub /) {
            val = sprintf("{\"code\": %s}", key, val);
            return;
        }
        # otherwise ensure that this is a hash
        #if (val !~ /\s*\(\s*('.+'|".+")\s*:/)
        #    error("key %y is not assigned to a hash; value: %y", key, val);
    }

    hash<auto> getInfo(*bool full) {
        hash<auto> h = self{"mapperid", "name", "version", "patch", "desc", "parse_options", "created", "modified"} +
            {"type": mtype.getName()};
        if (full) {
            h += {
                "option_source": option_source,
                "field_source": field_source,
                "fields": fields,
            };
        }
        return h;
    }

    private parseCommitImpl() {
        p.parseCommit();
    }

    abstract error(string fmt);
    abstract private loadLibraryImpl(MapperProgram p);

    Mapper create(*hash<auto> rtopts) {
        throw "UNSUPPORTED-ERROR", "cannot create mapper objects from this class";
    }
}

class MapperThreadData {
    constructor(Mappers mm) {
        save_thread_data(("mapper_info": ("mm": mm)));
    }

    destructor() {
        remove_thread_data("mapper_info");
    }

    static hash<auto> get() {
        return get_thread_data("mapper_info");
    }

    static Mappers getMappers() {
        return get_thread_data("mapper_info").mm;
    }

    static update(hash<auto> h) {
        save_thread_data(("mapper_info": h));
    }
}

public namespace OMQ {
    #! Mapper module API namespace
    namespace MapperModuleApi {
        #! mapper module API function for registering new mapper types in the module's init code
        sub map_register_mapper(OMQ::AbstractMapperType type) {
            (MapperThreadData::getMappers()).registerMapper(type);
        }
    }
}

public class OMQ::Mappers {
    public {
        const Modules = ("Util", "Mapper");
        const ClassList = (
            "QorusInboundTableMapper",
            "QorusInboundTableMapperIterator",
            "AbstractMapperType",
            "MapperType",
            "InboundTableMapperType",
            "QorusSqlStatementOutboundMapper",
            "QorusSqlStatementOutboundMapperType",
            "QorusRawSqlStatementOutboundMapper",
            "QorusRawSqlStatementOutboundMapperType",
        );

        const MapperProviderApi = (
            "map_register_mapper",
            {"import": "OMQ::UserApi::MapperProviderApi::log", "actual": "qlog"},
            "get_system_info",

            {"import": "OMQ::UserApi::MapperProviderApi::map_try_get_wf_static_data", "actual": "qorus_api_svc_try_get_wf_static_data"},
            {"import": "OMQ::UserApi::MapperProviderApi::map_try_get_wf_dynamic_data", "actual": "qorus_api_svc_try_get_wf_dynamic_data"},
            {"import": "OMQ::UserApi::MapperProviderApi::map_try_get_wf_temp_data", "actual": "qorus_api_svc_try_get_wf_temp_data"},
        );
    }

    private {
        #! log closure
        code logc;

        #! mapper hash, keyed by mapperid, values are MapperContainerBase objects
        hash<string, MapperContainerBase> mh();

        #! mapper provider hash (from schemes)
        hash<string, list<string>> ph();

        #! read-write lock for atomicity
        RWLock rwl();

        #! mapper type hash: keys: info, type
        hash<string, AbstractMapperType> sh();

        #! internal mapper types
        hash<string, bool> ish;
    }

    constructor() {
        map registerMapperTypeIntern($1), (
            new MapperType(),
            new InboundTableMapperType(),
            new QorusSqlStatementOutboundMapperType(),
            new QorusRawSqlStatementOutboundMapperType(),
        );

        ish = map {$1: True}, keys sh;
    }

    #! creates the object and sets the log code reference/closure
    init(*code log, *softlist mml) {
        logc = log ? log : \OMQ::Mappers::logDefault();

        setupIntern(mml);

        # initialize mappers in the background so the HTTP server startup is not delayed
        background reload();
    }

    reload(*softlist ids) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        reloadIntern(ids);
    }

    abstract private reloadIntern(*softlist ids);

    abstract private setupIntern(*list mml);

    private loadMapperModule(Program pgm, string mod) {
        pgm.loadApplyToPrivateUserModule(mod);
    }

    list<string> addMapperTypeProvider(string mod) {
        MapperThreadData mtd(self);

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (ph{mod})
            return cast<list<string>>(ph{mod});

        Program pgm(CommonParseOptions);

        # setup API
        map pgm.loadModule($1), Modules;
        map pgm.importClass($1), ClassList;
        pgm.importGlobalVariable("omqservice");

        # import all library functions to mapper provider program
        map $1.import ? pgm.importFunction($1.actual, $1.import) : pgm.importFunction($1), MapperProviderApi;
%ifdef QorusServer
        pgm.setScriptPath(sprintf("%s/%s/%s", Qorus.options.get("instance-key"), "Mapper", mod));
%endif
        loadMapperModule(pgm, mod);

        hash<auto> mih;
        mih += MapperThreadData::get();
        if (mih.error)
            throw mih.error.err, sprintf("%s: %s", get_ex_pos(mih.error), mih.error.desc), mih.error.arg;

        if (!mih.sh)
            throw "MAPPER-ERROR", sprintf("mapper %y did not register any system mappers", mod);

        return cast<list<string>>(ph{mod} = mih.sh.keys());
    }

    registerMapper(AbstractMapperType amt) {
        hash<auto> mih;
        mih += MapperThreadData::get();
        on_exit MapperThreadData::update(mih);

        try {
            registerMapperTypeIntern(amt);
            mih.sh.(amt.getName()) = amt;
        } catch (hash<ExceptionInfo> ex) {
            mih.error = ex;
        }
    }

    registerMapperType(AbstractMapperType amt) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        registerMapperTypeIntern(amt);
    }

    private registerMapperTypeIntern(AbstractMapperType amt) {
        string mtn = amt.getName();
        if (sh{mtn})
            throw "MAPPER-ERROR", sprintf("mapper type %y is already registered", mtn);

        sh{mtn} = amt;
    }

    # like getInfo() but throws an exeption for unknown mappers
    *hash<auto> getInfoEx(softstring mapperid, *bool full) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        try {
            *MapperContainerBase m = mh{mapperid};
            if (m) {
                return m.getInfo(full);
            }
        } catch (hash<ExceptionInfo> ex) {
            log("mapperid %y: %s", mapperid, get_exception_string(ex));
            rethrow;
        }
        throw "UNKNOWN-MAPPER", sprintf("napper %d is unknown", mapperid);
    }

    *hash<auto> getInfo(softstring mapperid, *bool full) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        try {
            *MapperContainerBase m = mh{mapperid};
            return m ? m.getInfo(full) : NOTHING;
        } catch (hash<ExceptionInfo> ex) {
            log("mapperid %y: %s", mapperid, get_exception_string(ex));
            rethrow;
        }
    }

    *list<hash<auto>> listMappers(*bool full) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return map $1.getInfo(full), mh.iterator();
    }

    *list<hash<auto>> listProviders() {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return map getProviderInfoIntern($1), sh.iterator();
    }

    *hash<auto> getProvider(string type) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        *AbstractMapperType mt = sh{type};
        return mt ? getProviderInfoIntern(mt) : NOTHING;
    }

    private hash<auto> getProviderInfoIntern(AbstractMapperType mt) {
        string name = mt.getName();

        hash<auto> h;
        # make sure that "h" stays "hash<auto>"
        h += mt.getConfigInfo();
        if (ish{name}) {
            h.type = "system";
        } else {
            h += {
                "type": "user",
                "module": get_module_hash(){name},
            };
        }

        # note: we cannot get module info here because the module is loaded privately
        return h;
    }

    Mapper get(softstring mapperid, *hash<auto> rtopts) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return getIntern(mapperid, rtopts);
    }

    private Mapper getIntern(softstring mapperid, *hash<auto> rtopts) {
        return getMapperContainer(mapperid).create(rtopts);
    }

    # must be called in either the read or write lock
    private MapperContainerBase getMapperContainer(softstring mapperid) {
        *MapperContainerBase mcb = mh{mapperid};
        if (!mcb) {
            throw "MAPPER-ERROR", sprintf("cannot retrieve unknown mapperid %d; known mappers: %y", mapperid, (map $1.toInt(), keys mh));
        }
        return mcb;
    }

    AbstractIterator getIterator(softstring mapperid, AbstractIterator i, *hash<auto> rtopts) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return getIteratorIntern(mapperid, i, rtopts);
    }

    log(string fmt) {
        fmt = "Mappers: " + fmt;
        call_function_args(logc, list(fmt) + (argv ? argv : NOTHING));
    }

    private AbstractIterator getIteratorIntern(softstring mapperid, AbstractIterator i, *hash<auto> rtopts) {
        if (!mh{mapperid})
            throw "MAPPER-ERROR", sprintf("cannot retrieve iterator for unknown mapper %d; known mappers: %y", mapperid, (map $1.toInt(), keys mh));

        return mh{mapperid}.createIterator(i, rtopts);
    }

    #! the default logging action is to print out the log message to stderr
    private static logDefault(string msg) {
        stderr.vprintf(msg + "\n", argv);
        stderr.sync();
    }
}
