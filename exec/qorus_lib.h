/*
    qorus_lib.h
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

#ifndef _QORUS_LIB_H

#define _QORUS_LIB_H

#include <string>
#include <map>
#include <functional>

class QoreProgram;

struct qorus_dbg_t {
    bool internals = false;
    bool messages = false;
    bool config_items = false;

    DLLLOCAL void setDefines(QoreProgram& pgm) const;
};

typedef std::function<void (const std::string&, int64& po)> q_dbg_opt_func_t;
typedef std::map<std::string, q_dbg_opt_func_t> opt_map_t;

// Qorus is not under the GPL but rather this enables all modules to be loaded
#define QORUS_LICENSE QL_GPL

//#define QORUS_PARSE_OPTIONS (PO_REQUIRE_OUR|PO_STRICT_ARGS|PO_NO_CHILD_PO_RESTRICTIONS|PO_ALLOW_INJECTION)
#define QORUS_PARSE_OPTIONS (PO_REQUIRE_OUR|PO_NO_CHILD_PO_RESTRICTIONS|PO_ALLOW_INJECTION|PO_ALLOW_DEBUGGER)
#define QORUS_WARN_MASK (QP_WARN_ALL & ~QP_WARN_UNREFERENCED_VARIABLE & ~QP_WARN_MODULE_ONLY)
#define QORUS_PGM "qorus"

// adds qorus module paths to the beginning of the search path
DLLLOCAL void qorus_setup_module_paths(const char* argv0);
DLLLOCAL void qorus_init_pgm(QoreNamespace& ns);
DLLLOCAL void init_error();
DLLLOCAL qorus_dbg_t qorus_parse_options(int argc, char* argv[], int64& po, const opt_map_t& opt_map);

#endif
