#!/usr/bin/env qore
# -*- mode: qore; indent-tabs-mode: nil -*-
#
# Qorus Integration Engine
#
# Qorus YAML Object Parser script

/*
  Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

  **** NOTICE ****
    All information contained herein is, and remains the property of Qore
    Technologies, s.r.o. and its suppliers, if any.  The intellectual and
    technical concepts contained herein are proprietary to Qore Technologies,
    s.r.o. and its suppliers and may be covered by Czech, European, U.S. and
    Foreign Patents, patents in process, and are protected by trade secret or
    copyright law.  Dissemination of this information or reproduction of this
    material is strictly forbidden unless prior written permission is obtained
    from Qore Technologies, s.r.o.
*/

%requires qore >= 0.9

# here we add fallback paths to the QORE_INCLUDE_DIR search path,
# in case QORE_INCLUDE_DIR is not set properly
%append-include-path /var/opt/qorus/qlib:$OMQ_DIR/qlib:/opt/qorus/qlib

%new-style
%strict-args
%require-types
%enable-all-warnings

%exec-class qyaml

%requires yaml
%requires Qyaml

class qyaml {
    private {
        const opts = {
            "help": "h,help",
            "validate": "l,validate"
        };
    }

    static private usage() {
        printf("usage: %s [options] [file]\n"
               "ACCEPTED FILE EXTENSIONS:\n"
               " <file>.yaml          qorus object YAML definition\n"
               "OPTIONS:\n"
               " -h,--help            shows this help text\n"
               " -l,--validate        validate YAML file\n",
            get_script_name(),
        );
    }

    constructor() {
        GetOpt get_opt(opts);
        hash options = get_opt.parse3(\ARGV);

        if (options{"help"}) {
            usage();
            exit(0);
        }

        if (!ARGV) {
            print("No files are provided!\n");
            exit(1);
        }

        hash<string, hash<auto>> parsed_yaml_files = Qyaml::parse(cast<list<string>>(ARGV));
        if (options{"validate"}) {
            foreach hash<auto> i in (parsed_yaml_files.pairIterator()) {
                Qyaml::Validator validator = create_validator(i.value.type);
                Qyaml::ParsedYaml parsed_yaml_object(i.value);
                validator.validate(i.key, parsed_yaml_object);
                parsed_yaml_files{i.key} = parsed_yaml_object.data_;
            }
        }

        print(make_yaml(parsed_yaml_files));
    }
}
