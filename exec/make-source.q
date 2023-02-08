#!/usr/bin/env qore
# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%exec-class makeSource

%enable-all-warnings
%strict-args
%new-style
%require-types

const Opts = {
    "mod": "m,module",
    "debug": "d,debug",
    "help": "h,help",
};

class makeSource {
    public {
        hash opt;
    }

    constructor() {
        GetOpt g(Opts);
        opt = g.parse3(\ARGV);
        *string file = shift ARGV;
        if (!file)
            throw "ERROR", "filename required";

        makeSource(file);
    }

    static private string transform(string name) {
        name =~ s/-/_/g;
        return name;
    }

    private makeSource(string fn) {
        string bn = basename(fn);

        string func;
        if (bn == "qorus.q")
            func = "qorus_q";
        else {
            func = "qorus_" + makeSource::transform(bn);
            func =~ s/\..+$//;
        }

        # make output file name
        string ofn = "x_" + bn + ".cpp";
        #printf("%s -> %s: %s()\n", fn, ofn, func);

        # read in input file
        string str = ""; #"%old-style\n";
        foreach string line in (new FileLineIterator(fn)) {
            #if (line[0] == "%" && line !~ /^%(if|endif|else|push-parse-options|new-style|allow-bare-refs|require-types|strict-args)/)
            #    delete line;
            if (line[0] == "%" && line !~ /^%(if|endif|else|try-module|endtry|push-parse-options|strict-args|module-cmd)/)
                delete line;

            # remove "public" from declarations in modules
            if (opt.mod) {
                line =~ s/public[[:blank:]]+(class|const|namespace|our)[[:blank:]]/$1 /g;
                line =~ s/public[[:blank:]]+(.*)sub/$1sub/g;
            }

            str += line + "\n";
        }
        #printf("%s\n", str); exit(1);

        # compress buffer
        binary buf = compress(str, 9);

        #printf("compressed buffer for %s: %N\n", fn, buf);

        File of();
        of.open(ofn, O_WRONLY | O_CREAT | O_TRUNC, 0644);

        #of.printf("//xbuf=%d, buf=%d\n", elements xbuf, elements buf);

        of.print("
#include <qore/Qore.h>
#include <zlib.h>
#include <stdlib.h>
#include <pcre.h>

#include \"qorus_lib.h\"\n\n");

        of.printf("void %s", func);
        of.print("(bool debug_qorus_internals, QoreProgram *qpgm, ExceptionSink *xsink) {\n    QoreString str;\n");

        of.print("    unsigned char buf[] = {");
        for (int i = 0; i < elements buf; ++i) {
            of.printf("%d, ", get_byte(buf, i));
            if (!(i % 20)) {
                of.printf("\n        ");
            }
        }
        of.printf("};

    unsigned long size = %d;
    str.reserve(%d);
    uncompress((Bytef*)str.c_str(), &size, (Bytef*)buf, %d);
    str.terminate(%d);
", str.size() + 1, str.size() + 1, buf.size(), str.size());

        # remove QDBG_ lines for non-debugging runs of Qorus
        of.print("    if (!debug_qorus_internals) {\n");
        of.print("        QoreString match(\"^([^\\\\n]*?QDBG_[A-Z_]+\\\\(.*?\\\\).*?;)$\");\n");
        of.print("        QoreString subst(\"/*$1*/\");\n");
        of.print("        str.regexSubstInPlace(match, subst, QS_RE_GLOBAL | QS_RE_DOTALL | QS_RE_MULTILINE, xsink);\n");
        of.print("    }\n");
        of.printf("    qpgm->parsePending(str.getBuffer(), \"%s\", xsink, xsink, QORUS_WARN_MASK);\n", bn);
        of.print("}\n");
    }
}
