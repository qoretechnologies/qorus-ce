/*
    qorus_main.cpp
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

#include <qore/Qore.h>

#include "qorus_lib.h"
#include "ql_omqlib.h"

#include <stdio.h>
#include <libgen.h>
#include <stdlib.h>
#include <strings.h>
#include <dlfcn.h>
#include <string.h>

#if _Q_WINDOWS
#include <windows.h>
#endif

#include <string>

void qorus_q(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_common_master_core_client(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_version(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

// cluster support
void qorus_AbstractLogger(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusClientProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusClusterApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusExternProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusInterfaceProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusInternProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_LogPipeWrapper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ConfFileFromTemplate(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_NetworkKeyHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_PrometheusProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_GrafanaProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QdspProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QjobProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusCoreProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusOptionsBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusProcessManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSharedApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QsvcProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QwfProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusPassiveMasterProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMasterClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMasterCoreQsvcCommon(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusCommonLib(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRestartableTransaction(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

void qorus_cpc_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_core_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_dsp_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_job_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_master_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_svc_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_wf_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

// internal module function type
typedef void (*int_mod_t)(QoreString& str);

//#define DEBUG
#ifndef DEBUG
//#warning disabling signal handling
//#define QORE_OPTS QLO_DISABLE_SIGNAL_HANDLING
#define QORE_OPTS 0
#else
#define QORE_OPTS QLO_DISABLE_SIGNAL_HANDLING
// issue #1984: do not raise a c++ warning because it causes compilation to fail
//#warning disabling signal handling
#endif

// list of modules to be "compiled" and stored internally
// order is important; if a module is listed out of order, then it would load dependent modules from the filesystem
// allowing potentially user-modified modules to be a part of the server code
const char* int_modules[] = {
};

#define NUM_INT_MODULES (sizeof(int_modules) / sizeof(char*))

const char* req_modules[] = {
    "yaml",
    "json",
    "process",
    "zmq",
    "Util",
    "SqlUtil",
    "uuid",
    "sysconf",
    "Logger",
    "FsUtil",
    "reflection",
    "Qorize"
};

#define NUM_REQ_MODULES (sizeof(req_modules) / sizeof(char*))

static int my_load_mod(const char* name, QoreProgram* qpgm) {
    SimpleRefHolder<QoreStringNode> err(MM.parseLoadModule(name, qpgm));
    if (err) {
        fprintf(stderr, "ERROR: cannot load required module '%s': %s\n", name, err->getBuffer());
        return 1;
    }
    return 0;
}

#ifdef RTLD_MAIN_ONLY
#define DLSYM_ARG RTLD_MAIN_ONLY
#else
#define DLSYM_ARG RTLD_DEFAULT
#endif

int main(int argc, char* argv[]) {
    if (qore_version_major == 0 && (qore_version_minor < 9 || (qore_version_minor == 9 && qore_version_sub < 0))) {
        fprintf(stderr, "ERROR: incompatible qore library: >= 0.9 required, got %s instead, cannot start Qorus\n", qore_version_string);
        exit(1);
    }

    // add custom module directories (must be before qore_init())
    qorus_setup_module_paths(argv[0]);

    // add standard module directories afterwards
    MM.addStandardModulePaths();

    // initialize Qore subsystem
    qore_init(QORUS_LICENSE, "UTF-8", true, QORE_OPTS);

    // cleanup Qore subsystem on exit (deallocate memory, etc)
    ON_BLOCK_EXIT(qore_cleanup);

    // parse options for Qorus itself
    int64 po = PO_REQUIRE_OUR | PO_NEW_STYLE | PO_REQUIRE_PROTOTYPES | PO_STRICT_ARGS | PO_REQUIRE_TYPES | PO_ALLOW_WEAK_REFERENCES;

    // parse command line options that need to take effect before parsing Qorus
    qorus_dbg_t qorus_dbg = qorus_parse_options(argc, argv, po, opt_map_t());

    // setup the command line
    qore_setup_argv(1, argc, argv);

    QoreProgram* qpgm = new QoreProgram(po);

    // set define for Qorus server
    qpgm->parseDefine("QorusServer", true);
    qpgm->parseDefine("NeedQorusLoggerCache", true);
    qorus_dbg.setDefines(*qpgm);

#ifdef __linux__
    // set LINUX define on Linux
    qpgm->parseDefine("LINUX", true);
    qpgm->parseDefine("MEMORY_POLLING", true);
#elif defined(__APPLE__) && defined(__MACH__)
    // set DARWIN define on MacOS
    qpgm->parseDefine("DARWIN", true);
    qpgm->parseDefine("MEMORY_POLLING", true);
#endif

    // load required module(s)
    for (unsigned i = 0; i < NUM_REQ_MODULES; ++i) {
        if (my_load_mod(req_modules[i], qpgm))
            return 1;
    }

    ExceptionSink xsink;

   // setup internal modules
#if _Q_WINDOWS
    HMODULE hm = GetModuleHandle(0);
    if (!hm) {
        fprintf(stderr, "Qorus link error; cannot find module handle for current image\n");
        return -1;
    }
#endif

   for (unsigned i = 0; i < NUM_INT_MODULES; ++i) {
        QoreString str;
        QoreString name("qorus_");
        name.concat(int_modules[i]);
        int_mod_t f;
#if _Q_WINDOWS
        f = (int_mod_t)GetProcAddress(hm, name.getBuffer());
#else
        f = (int_mod_t)dlsym(DLSYM_ARG, name.getBuffer());
#endif
        if (!f) {
            fprintf(stderr, "Qorus link error; cannot find internal module symbol '%s'\n", name.getBuffer());
            return -1;
        }
        f(str);
        //printf("calling MM.registerUserModuleFromSource(name: '%s', src: <%ld bytes>, qpgm: %p)\n", int_modules[i], str.size(), qpgm);
        MM.registerUserModuleFromSource(int_modules[i], str.getBuffer(), qpgm, &xsink);
        if (xsink) {
            xsink.handleExceptions();
            return -1;
        }
    }

#if _Q_WINDOWS
    CloseHandle(hm);
#endif

    qpgm->parseSetParseOptions(QORUS_PARSE_OPTIONS);

    QoreNamespace* QNS = new QoreNamespace("Qorus");
    qpgm->setScriptPath(argv[0]);

    qorus_init_pgm(*QNS);

    // add custom code
    init_omqlib_functions(*QNS);
    init_omqlib_constants(*QNS);
    qpgm->getRootNS()->addInitialNamespace(QNS);

    qorus_q(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_common_master_core_client(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_version(qorus_dbg.internals, qpgm, &xsink);

    // cluster support
    qorus_AbstractLogger(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusClientProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusClusterApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusExternProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusInterfaceProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusInternProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_LogPipeWrapper(qorus_dbg.internals, qpgm, &xsink);
    qorus_ConfFileFromTemplate(qorus_dbg.internals, qpgm, &xsink);
    qorus_NetworkKeyHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_PrometheusProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_GrafanaProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_QdspProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_QjobProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusCoreProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusOptionsBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusProcessManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSharedApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_QsvcProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_QwfProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusPassiveMasterProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMasterClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMasterCoreQsvcCommon(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusCommonLib(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRestartableTransaction(qorus_dbg.internals, qpgm, &xsink);

    qorus_cpc_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_core_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_dsp_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_job_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_master_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_svc_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_wf_api(qorus_dbg.internals, qpgm, &xsink);

    qpgm->parseCommit(&xsink, &xsink, QORUS_WARN_MASK);

    int rc = 0;
    if (!xsink.isEvent())
        qpgm->runClass("QorusMaster", &xsink);

    qpgm->waitForTerminationAndDeref(&xsink);
    xsink.handleExceptions();

    return rc;
}
