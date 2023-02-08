#!/usr/bin/env qore
# -*- mode: qore; indent-tabs-mode: nil -*-
#
# Qorus Integration Engine
#
# Qorus Object Parser script
#

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

%exec-class qop

%requires QorusObjectParser
%requires json
%requires Logger

public namespace QorusObjectParser;

class qop {

    private {
        const opts = {
            "encoding": "e,encoding=s",
            "help": "h,help",
            "ignore-errors": "i,ignore-errors"
        };
    }

    static private usage() {
        printf("usage: qop [options] [file]\n"
               "ACCEPTED FILE EXTENSIONS:\n"
               " <file>.qfd         function definitions\n"
               " <file>.qsd         service definitions\n"
               " <file>.qsd.java    Java service definitions\n"
               " <file>.qjob        job definitions\n"
               " <file>.qjob.java   Java job definitions\n"
               " <file>.qclass      class definitions\n"
               " <file>.qclass.java Java class definitions\n"
               " <file>.qconst      constant definitions\n"
               " <file>.qmapper     mapper definition\n"
               " <file>.qvmap       value map definition\n"
               "OPTIONS:\n"
               " -e,--encoding       sets the encoding of the parser (default is utf-8)\n",
               " -h,--help           shows this help text\n"
               " -i,--ignore-errors  ignores any error and skip failed file (default is false)"
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

        if (!exists options{"ignore-errors"}) {
            options{"ignore-errors"} = False;
        }

        Parser parser();

        list result;
        foreach string file in (ARGV) {
            try {
                list<QorusObject> qorus_objects = parser.parse(file);
                foreach auto qorus_object in (qorus_objects) {
                    result += qorus_object.serializeMembers();
                }
            } catch (hash exception) {
                if ((exception.err == "QORUS-OBJECT-PARSER-ERROR" || exception.err == "INVALID-NAME")
                    && options{"ignore-errors"}) {

                    stderr.print(exception.err + ": " + file + ": " + exception.desc + "\n");
                    continue;
                }
                rethrow;
            }
        }
        printf("%s\n", make_json(result));
    }
}
