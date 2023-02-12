/*
    qorus_lib.cpp
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

#include <qore/Qore.h>

#include <stdio.h>
#include <stdlib.h>

#include "qorus_lib.h"

void qorus_setup_module_paths(const char* argv0) {
    SystemEnvironment::set("LANG", "C");
    SystemEnvironment::set("LC_ALL", "C");
    SystemEnvironment::set("LC_NUMERIC", "C");

    char* dir = getenv("OMQ_DIR");
    QoreString str;

    // if OMQ_DIR is not set, then try to determine the application directory from the current program's path
    if (!dir) {
        dir = q_dirname(argv0);
        str.sprintf("%s" QORE_DIR_SEP_STR "..", dir);
        free(dir);
    } else {
        str.concat(dir);
    }

    QoreString path(str);
    path.concat(QORE_DIR_SEP_STR "lib" QORE_DIR_SEP_STR "modules");
    //printf("module dir: %s\n", path.getBuffer());
    MM.addModuleDir(path.getBuffer());

    path.set(str);
    path.concat(QORE_DIR_SEP_STR "qlib");
    //printf("module dir: %s\n", path.getBuffer());
    MM.addModuleDir(path.getBuffer());

    path.set(str);
    path.concat(QORE_DIR_SEP_STR "user" QORE_DIR_SEP_STR "modules");
    //printf("module dir: %s\n", path.getBuffer());
    MM.addModuleDir(path.getBuffer());
}

const char* qorus_revision = QORUS_REVISION;
const char* qorus_build_host = QORUS_BUILD_HOST;
int64 qorus_build_time = QORUS_BUILD_TIME;
const char* qorus_build_user = QORUS_BUILD_USER;

void qorus_init_pgm(QoreNamespace& ns) {
    ns.addConstant("QorusRevision", new QoreStringNode(qorus_revision));
    ns.addConstant("QorusBuildHost", new QoreStringNode(qorus_build_host));
    ns.addConstant("QorusBuildTime", new DateTimeNode(qorus_build_time));
    ns.addConstant("QorusBuildUser", new QoreStringNode(qorus_build_user));
}

void init_error() {
    fprintf(stderr, "corrupted file, cannot initialize, aborting\n");
    exit(1);
}

// trim from start (in place)
static void ltrim(std::string& s) {
    s.erase(s.begin(), std::find_if(s.begin(), s.end(), [](int ch) {
        return !std::isspace(ch);
    }));
}

// trim from end (in place)
static void rtrim(std::string& s) {
    s.erase(std::find_if(s.rbegin(), s.rend(), [](int ch) {
        return !std::isspace(ch);
    }).base(), s.end());
}

// trim from both ends (in place)
static void trim(std::string& s) {
    ltrim(s);
    rtrim(s);
}

//static q_dbg_opt_func_t example = [] (const std::string& val) { };

void qorus_dbg_t::setDefines(QoreProgram& pgm) const {
    if (internals) {
        pgm.parseDefine("QorusDebugInternals", true);
    }
    if (messages) {
        pgm.parseDefine("QorusDebugMessages", true);
    }
    if (config_items) {
        pgm.parseDefine("QorusDebugConfigItems", true);
    }
}

/*
   here we process options that need to go into effect before
   the server code is created

   to do this, first we process the command-line arguments,
   which override options in the option file, and then, if
   necessary, we process the option file, also taking into
   consideration any "option-file" option specified on the
   command line
 */
qorus_dbg_t qorus_parse_options(int argc, char* argv[], int64& po, const opt_map_t& opt_map) {
    qorus_dbg_t qorus_dbg;
#ifdef DEBUG
    qorus_dbg.internals = true;
#endif

    std::string option_file;

    // first parse the command line
    for (int i = 1; i < argc; ++i) {
        char* p = strchr(argv[i], '=');
        if (!p)
            continue;
        if (!strncmp(argv[i], "option-file", 11)) {
            option_file = ++p;
            continue;
        }
        // ignore all other options
    }

    // now parse the options file if necessary
    // get standard option file location if necessary
    if (option_file.empty()) {
        QoreString val;
        if (!SystemEnvironment::get("OMQ_DIR", val)) {
            if (val == "LSB")
                option_file = "/etc/qorus/options";
            else {
                option_file = val.c_str();
                option_file += QORE_DIR_SEP;
                option_file += "etc";
                option_file += QORE_DIR_SEP;
                option_file += "options";
            }
            //printd(5, "got option file: '%s'\n", option_file.c_str());
        }
    }

    // parse option file if present
    if (!option_file.empty()) {
        QoreFile f;
        if (!f.open(option_file.c_str())) {
            QoreString val;
            while (true) {
                if (f.readLine(val))
                    break;
                val.trim();
                if (val.empty() || val[0] == '#')
                    continue;
                qore_offset_t i = val.find(':');
                if (i < 0) {
                    i = val.find('=');
                    if (i < 0)
                        continue;
                }
                std::string optval(val.c_str() + i + 1);
                val.terminate(i);
                trim(optval);
                val.trim();
                //printd(5, "val: '%s' = '%s'\n", val.c_str(), optval.c_str());
                if (val == "qorus.debug-qorus-internals") {
                    if (optval == "false") {
                        qorus_dbg.internals = false;
                        continue;
                    }
                    qorus_dbg.internals = true;
                    if (optval.find("msg") != std::string::npos) {
                        qorus_dbg.messages = true;
                    }
                    if (optval.find("cfgitems") != std::string::npos) {
                        qorus_dbg.config_items = true;
                    }
                    continue;
                }
                {
                    opt_map_t::const_iterator i = opt_map.find(val.c_str());
                    if (i != opt_map.end()) {
                        i->second(optval, po);
                    }
                }
            }
        }
    }

    if (!qorus_dbg.internals) {
        po |= PO_NO_DEBUGGING;
    }

    return qorus_dbg;
}

