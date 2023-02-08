# -*- mode: qore; indent-tabs-mode: nil -*-
# QorusObjectParser.ql contains definitons of constants and functions for QorusObjectParser module

public namespace QorusObjectParser {
    #! for constant library objects
    public const OT_CONSTANT = "CONSTANT";
    #! for class library objects
    public const OT_CLASS    = "CLASS";
    #! for function library objects
    public const OT_FUNCTION = "FUNCTION";
    #! for mappers objects
    public const OT_MAPPER = "MAPPER";
    #! for value maps objects
    public const OT_VALUE_MAP = "VALUE_MAP";

    #! for pipeline objects
    /** @since Qorus 5.0 */
    public const OT_PIPELINE = "PIPELINE";
    #! for FSM objects
    /** @since Qorus 5.0 */
    public const OT_FSM = "FSM";

    #! Allow a dot in the name
    const N_WITH_DOT      = (1 << 0);
    #! Allow email addresses
    const N_EMAIL_ADDRESS = (1 << 1);

    #! Validates Qorus object (service, workflow, job, ...) names
    /**
        @param name The object name
        @param rules if present, a bitfield made up of @ref N_WITH_DOT or @ref N_EMAIL_ADDRESS

        @returns True if \a name is valid otherwise False

        Note: empty names are allowed and are valid
    */
    public bool sub is_valid_object_name(*string name, *int rules) {
        switch (rules) {
            case N_WITH_DOT:
                return (name !~ /[^[:alnum:]-_\.]/u);

            case N_EMAIL_ADDRESS:
                return (name !~ /[^[:alnum:]-_\.@]/u);
        }
        return (name !~ /[^[:alnum:]-_]/u);
    }

    #! Validates Qorus object (serivce, workflow, job, ...) name
    /** Allowed characters are a-z A-Z 0-9 - _
        @param name The object name
        @param rules if present, a bitfield made up of @ref N_WITH_DOT or @ref N_EMAIL_ADDRESS

        @throws INVALID-NAME exception whenever name is invalid

        Note: empty name is allowed and valid
    */
    public sub validate_object_name(*string name, *int rules) {
        if (!is_valid_object_name(name, rules)) {
            throw "INVALID-NAME",
                sprintf("invalid characters in name %y; allowed name format: [A-Za-z0-9-_]*", name);
        }
    }

    #! default description length in bytes for user objects
    public const SQLDescLen = 4000;

    #! length of name columns in bytes
    public const SQLNameLen = 160;

    #! length of author columns in bytes
    public const SQLAuthorLen = 240;

    #! length of patch columns in bytes
    public const SQLPatchLen = 80;

    #! length of version columns in bytes
    public const SQLVersionLen = 80;

    /** @defgroup TagDefinitions Tag Definitions
        These constants define information about tags that define attributes of function, job, service, class, and
        constant files when parsing.\n
        \n
        tag format: a hash where the keys are the option names, and the values
        are hashes describing how the options should be parsed; option hashes
        can have the following keys:
        - \c mandatory: boolean - if an error should be raised if the tag is not present
        - \c multi: string - allow the tag to be defined more than once; subsequent instances of the tag will be
          concatenated to the option value with the value of the \c "multi" option
        - \c warn: boolean - print a warning if the tag is not defined
        - \c maxlen: check the maximum length of the string in bytes, warn if it's over this length, and truncate the
          string to this byte length
        - \c list: boolean - if True then this option will take multiple values and will be returned as a list
        - \c type: string - the data type of the tag, so far \c "bool", \c "int", and \c "date" have been implemented
    */
    #/@{

    #! common definition of the name tag
    public const NameTagParams = {"maxlen": SQLNameLen};

    #! name tag definition
    public const NameTag = {"name": NameTagParams};

    #! name tag definition for objects where the tag is required
    public const NameTagReq = {"name": NameTagParams + {"mandatory": True}};

    #! version tag definition
    public const VersionTag = {"version": {"mandatory": True, "maxlen": SQLVersionLen}};

    #! desc tag definition
    public const DescTag = {"desc": {"maxlen": SQLDescLen, "multi": " ", "warn": True}};

    #! author tag definition
    public const AuthorTag = {"author": {"maxlen": SQLAuthorLen, "list": True}};

    #! patch tag definition
    public const PatchTag = {"patch": {"maxlen": SQLPatchLen}};

    #! function type tag definition
    public const FuncTypeTag = {"type": {"mandatory": True}};

    #! lang tag definition
    public const LangTag = {"lang": {"maxlen": 80, "values": ("qore", "java"), "default": "qore"}};

    #! requires tag definition
    public const RequiresTag = {"requires": {"list": True}};

    #! class-name tag definition
    public const ClassNameTag = {"class-name": {"maxlen": SQLNameLen}};

    #! common to many files
    public const CommonBaseTags = VersionTag + DescTag + AuthorTag;

    #! common to functions, classes, and constants
    public const CommonGenericTags = CommonBaseTags + PatchTag;

    #! tags for function files
    public const FunctionTags = NameTag + CommonGenericTags + FuncTypeTag;

    #! tags for class files
    public const ClassTags = NameTag + LangTag + RequiresTag + CommonGenericTags;

    #! tags for constant files
    public const ConstantTags = NameTagReq + CommonGenericTags;

    public const BaseLibTags = {
        "constants": {"list": True, "mandatory": False},
        "classes": {"list": True, "mandatory": False},
        "functions": {"list": True, "mandatory": False},
    };

    #! tags for library objects
    public const LibTags = BaseLibTags + {
        "mappers": {"list": True, "mandatory": False},
        "vmaps": {"list": True, "mandatory": False},
    };

    #! tags for groups
    public const GroupTags = {
        "define-group": {"list": True},
        "groups": {"mandatory": False},
    };

    #! tags for complex files
    public const ComplexTags = CommonBaseTags + LibTags + GroupTags;

    #! class-based tag
    public const ClassBasedTag = {"class-based": {"type": Type::Boolean}};

    #! tags for job files
    public const JobTags = NameTagReq + ComplexTags + LangTag + ClassBasedTag + ClassNameTag + {
        "single-instance": {"type": Type::Boolean, "default": False},
        "active": {"type": Type::Boolean, "default": True},
        "run-skipped": {"type": Type::Boolean, "default": True},
        "schedule": {"mandatory": False},
        "duration": {"mandatory": False},
        "expiry-date": {"type": Type::Date},
        "remote": {"type": Type::Boolean},
        "job-modules": {"list": True,},
    };

    #! tags for service methods
    const ServiceMethodTags = NameTag + CommonBaseTags - ("version") + {
        "lock": {"mandatory": False, "default": "none"},
        "internal": {"type": Type::Boolean},
        "write": {"type": Type::Boolean},
        "import-code": {"mandatory": False},
        "define-auth": {"mandatory": False}
    };

    #! tags for service files
    public const ServiceTags = LibTags + GroupTags + LangTag + ClassBasedTag + ClassNameTag + {
        "servicetype": {"mandatory": False, "default": "USER"},
        "service": {"maxlen": SQLNameLen},
        "servicedesc": {"multi": " ", "maxlen": SQLDescLen},
        "serviceauthor": {"multi": ", ", "maxlen": SQLAuthorLen},
        "servicepatch": {"maxlen": SQLPatchLen},
        "serviceversion": {"maxlen": SQLVersionLen},
        "resource": {"list": True, "mandatory": False},
        "text-resource": {"list": True, "mandatory": False},
        "bin-resource": {"list": True, "mandatory": False},
        "template": {"list": True, "mandatory": False},
        "autostart": {"type": Type::Boolean, "default": False},
        "remote": {"type": Type::Boolean},
        "parse-options": {"mandatory": False},
        "service-modules": {"list": True,},
        "define-auth-label": {"mandatory": False},
    };

    #! tags for mapper files
    public const MapperTags = NameTag + CommonGenericTags + BaseLibTags + GroupTags + {
        "type": {"maxlen": SQLNameLen},
        "parse-options": {"mandatory": False},
    };

    #! tags for value maps
    public const ValueMapTags = NameTag + DescTag + AuthorTag + {
        "define-group": {"list": True},
        "groups": {"mandatory": False},
        "exception": {"type": Type::Boolean},
        "valuetype": {"maxlen": 6, "mandatory": True},
        "dateformat": {"maxlen": 160},
    };
    #/@}

    /** @defgroup StepFunctionTypes Step Function Types
        These are the possible function types for step functions
    */
    #/@{
    #! step function type
    public const FT_Step        = "STEP";
    #! generic function type
    public const FT_Generic     = "GENERIC";
    #! async start function type for async steps
    public const FT_AsyncStart  = "ASYNC-START";
    #! async end function type for async steps
    public const FT_AsyncEnd    = "ASYNC-END";
    #! validation function type
    public const FT_Validation  = "VALIDATION";
    #! array function type
    public const FT_Array       = "ARRAY";
    #! subworkflow function type
    public const FT_Subworkflow = "SUBWORKFLOW";
    #/@}

    #! list of all valid function types
    public const AllFunctionTypes = (FT_Step, FT_Generic, FT_AsyncStart, FT_AsyncEnd, FT_Validation, FT_Array,
        FT_Subworkflow);

    /** @defgroup MethodLockAttributes Service Method Lock Attribute Values
        These are the possible values for the lock attribute of a service method
    */
    #/@{
    #! service lock type: none
    public const SLNone  = "none";
    #! service lock type: read
    public const SLRead  = "read";
    #! service lock type: write
    public const SLWrite = "write";
    #/@}

    #! list of all service lock types
    public const AllSLTypes = (SLNone, SLRead, SLWrite);

    #! valid additional parse options for services
    public const ParseOptionList = (
        PO_REQUIRE_TYPES,
        PO_REQUIRE_PROTOTYPES,
        PO_STRICT_ARGS,
        PO_ASSUME_LOCAL,
        PO_ALLOW_BARE_REFS,
    );

    # mask of valid parse options for mappers
    public const ParseOptionMask = foldl $1 | $2, ParseOptionList;

    # mapping from library tags to database library types
    public const TagToLibraryType = {
        "functions": OT_FUNCTION,
        "classes": OT_CLASS,
        "constants": OT_CONSTANT,
        "mappers": OT_MAPPER,
        "vmaps": OT_VALUE_MAP,
        "pipeline": OT_PIPELINE,
        "fsm": OT_FSM,
    };
}
