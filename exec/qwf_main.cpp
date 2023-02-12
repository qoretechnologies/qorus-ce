/*
    qwf_main.cpp
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

#include "QC_SegmentEventQueue.h"
#include "QC_TimedWorkflowCache.h"

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

void qorus_QorusInterfaceProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusDistributedProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusDebugLogger(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusDebugProgramSource(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusDistributedProcessWithDebugProgramControl(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusClusterApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusClientProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMasterClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractLogger(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSharedApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QdspClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_version(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_master_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_core_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_wf_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_dsp_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

void qorus_ControlBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ClusterControl(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractDatasourceManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ClientDatasourceManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ThreadLocalData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Map(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusClusterOptions(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Workflow(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractWorkflowQueue(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WorkflowQueueBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ClusterWorkflowQueue(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Mappers(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMappers(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServerMapperContainer(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_OmqMap(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMapManagerBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMapManagerClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_SQLInterface(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServerSQLInterface(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Audit(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AuditRemote(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_SegmentManagerBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ClusterSegmentManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WFEntry(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WFEntryCache(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_StepDataHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_TempDataHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_DynamicDataHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_SensitiveDataHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_OrderData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_OrderInstanceNotes(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractWorkflowExecutionInstance(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WorkflowExecutionInstance(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ClusterWorkflowExecutionInstance(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_InstanceData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WorkflowUniqueKeyHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractSegmentWorkflowData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_LocalSegmentWorkflowData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ClusterSegmentWorkflowData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSystemRestHelperBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSystemAPIHelperBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMethodGateHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusServiceHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRemoteServiceHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Connections(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusCoreSubsystemClientBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusLogWebSocketHandlerClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Streams(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusUserConnectionsClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServerConnectionsClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteMonitorClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusControlClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Session(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServerSessionBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QwfServerSession(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ActionReason(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_CodeActionReason(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_NetworkKeyHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_UserApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_MapperApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WorkflowApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusConfigurationItemProvider(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusWorkflow(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusStepBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusAsyncStepBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusEventStepBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSubworkflowStepBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusAsyncArrayStep(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusAsyncStep(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusEventArrayStep(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusEventStep(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusNormalArrayStep(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusNormalStep(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSubworkflowArrayStep(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSubworkflowStep(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusCommonInterface(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusClientServer(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusDataProviderTypeHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_CommonInterfaceBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ObserverPattern(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusLocalRestHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_InterfaceContextHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ClusterServiceManagerClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusCommonLib(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRestartableTransaction(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

void qorus_Fsm(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusFsmHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusPipelineFactory(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

void qorus_qorus(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_shared_system(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_wf_core_system(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_wf_system(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_misc(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_common_master_core_client(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_cluster_common_server_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

void qorus_qwf(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

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
    "zmq",
    "uuid",
    "xml",
    "yaml",
    "json",
    "process",
    "reflection",
    "Util",
    "Mapper",
    "TableMapper",
    "SqlUtil",
    "YamlRpcClient",
    "DataStreamUtil",
    "DataStreamClient",
    "TelnetClient",
    "WebSocketClient",
    "Ssh2Connections",
    "XmlRpcConnection",
    "JsonRpcConnection",
    "SoapClient",
    "SmtpClient",
    "Pop3Client",
    "RestClient",
    "Swagger",
    "Sap4HanaRestClient",
    "SewioRestClient",
    "SewioWebSocketClient",
    "AwsRestClient",
    "SalesforceRestClient",
    "BulkSqlUtil",
    "Logger",
    "CsvUtil",
    "FsUtil",
    "DebugUtil",
    "DebugProgramControl",
    "ZeyosRestClient",
    "Qorize",
    "DbDataProvider",
    "FileLocationHandler",
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
#ifdef DEBUG_1   //_1 how set in cmake ?
    debug = 5;
    qore_trace = 1;
#endif

    if (qore_version_major == 0 && (qore_version_minor < 9 || (qore_version_minor == 9 && qore_version_sub < 0))) {
        fprintf(stderr, "ERROR: incompatible qore library: >= 0.9 required, got %s instead, cannot start Qorus\n",  qore_version_string);
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
    int64 po = PO_REQUIRE_OUR | PO_NEW_STYLE | PO_STRICT_ARGS | PO_REQUIRE_TYPES | PO_ALLOW_WEAK_REFERENCES;

    // parse command line options that need to take effect before parsing Qorus
    qorus_dbg_t qorus_dbg = qorus_parse_options(argc, argv, po, opt_map_t());

    // setup the command line
    qore_setup_argv(1, argc, argv);

    QoreProgram* qpgm = new QoreProgram(po);
    qpgm->setScriptPath(argv[0]);

    // set define for the qwf server
    qpgm->parseDefine("QorusServer", true);
    qpgm->parseDefine("QorusHasWfApi", true);
    qpgm->parseDefine("QorusHasAnyIxApi", true);
    qpgm->parseDefine("QorusClusterServer", true);
    qpgm->parseDefine("QorusQwfServer", true);
    qorus_dbg.setDefines(*qpgm);

    // load required module(s)
    for (unsigned i = 0; i < NUM_REQ_MODULES; ++i) {
        if (my_load_mod(req_modules[i], qpgm))
            return 1;
    }

    // try to load the oracle module for functions required by SQLInterface and ServerSQLInterface
    {
        SimpleRefHolder<QoreStringNode> err(MM.parseLoadModule("oracle", qpgm));
        if (err)
            qpgm->parseDefine("NO_ORACLE", true);
        else {
	        err = MM.parseLoadModule("OracleExtensions", qpgm);
	        if (err) {
	            fprintf(stderr, "ERROR: cannot load required module 'OracleExtensions' (required when the 'oracle' module is present): %s\n", err->getBuffer());
	            return 1;
	        }
        }
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
    qorus_init_pgm(*QNS);

    // add custom code
    init_omqlib_functions(*QNS);
    init_omqlib_constants(*QNS);

    QNS->addSystemClass(initSegmentEventQueueClass(*QNS));
    QNS->addSystemClass(initTimedWorkflowCacheClass(*QNS));

    qpgm->getRootNS()->addInitialNamespace(QNS);

    qorus_ThreadLocalData(qorus_dbg.internals, qpgm, &xsink);
    qorus_Map(qorus_dbg.internals, qpgm, &xsink);
    qorus_qwf(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusInterfaceProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusDebugLogger(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusDebugProgramSource(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusDistributedProcessWithDebugProgramControl(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusDistributedProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusClusterApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusClientProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMasterClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractLogger(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSharedApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_QdspClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_version(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_master_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_core_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_wf_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_dsp_api(qorus_dbg.internals, qpgm, &xsink);

    qorus_AbstractDatasourceManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_ClientDatasourceManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusClusterOptions(qorus_dbg.internals, qpgm, &xsink);
    qorus_Workflow(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractWorkflowQueue(qorus_dbg.internals, qpgm, &xsink);
    qorus_WorkflowQueueBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_ClusterWorkflowQueue(qorus_dbg.internals, qpgm, &xsink);
    qorus_Mappers(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMappers(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServerMapperContainer(qorus_dbg.internals, qpgm, &xsink);
    qorus_OmqMap(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMapManagerBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMapManagerClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_SQLInterface(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServerSQLInterface(qorus_dbg.internals, qpgm, &xsink);
    qorus_Audit(qorus_dbg.internals, qpgm, &xsink);
    qorus_AuditRemote(qorus_dbg.internals, qpgm, &xsink);
    qorus_ControlBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_ClusterControl(qorus_dbg.internals, qpgm, &xsink);
    qorus_SegmentManagerBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_ClusterSegmentManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_WFEntry(qorus_dbg.internals, qpgm, &xsink);
    qorus_WFEntryCache(qorus_dbg.internals, qpgm, &xsink);
    qorus_StepDataHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_TempDataHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_DynamicDataHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_SensitiveDataHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_OrderData(qorus_dbg.internals, qpgm, &xsink);
    qorus_OrderInstanceNotes(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractWorkflowExecutionInstance(qorus_dbg.internals, qpgm, &xsink);
    qorus_WorkflowExecutionInstance(qorus_dbg.internals, qpgm, &xsink);
    qorus_ClusterWorkflowExecutionInstance(qorus_dbg.internals, qpgm, &xsink);
    qorus_InstanceData(qorus_dbg.internals, qpgm, &xsink);
    qorus_WorkflowUniqueKeyHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSystemRestHelperBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSystemAPIHelperBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMethodGateHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusServiceHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRemoteServiceHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_Connections(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractSegmentWorkflowData(qorus_dbg.internals, qpgm, &xsink);
    qorus_LocalSegmentWorkflowData(qorus_dbg.internals, qpgm, &xsink);
    qorus_ClusterSegmentWorkflowData(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusCoreSubsystemClientBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusLogWebSocketHandlerClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusUserConnectionsClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServerConnectionsClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteMonitorClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusControlClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_Streams(qorus_dbg.internals, qpgm, &xsink);
    qorus_Session(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServerSessionBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QwfServerSession(qorus_dbg.internals, qpgm, &xsink);
    qorus_ActionReason(qorus_dbg.internals, qpgm, &xsink);
    qorus_CodeActionReason(qorus_dbg.internals, qpgm, &xsink);
    qorus_NetworkKeyHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_UserApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_MapperApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_WorkflowApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusConfigurationItemProvider(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusWorkflow(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusStepBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusAsyncStepBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusEventStepBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSubworkflowStepBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusAsyncArrayStep(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusAsyncStep(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusEventArrayStep(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusEventStep(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusNormalArrayStep(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusNormalStep(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSubworkflowArrayStep(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSubworkflowStep(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusCommonInterface(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusClientServer(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusDataProviderTypeHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_CommonInterfaceBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_ObserverPattern(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusLocalRestHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_InterfaceContextHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_ClusterServiceManagerClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusCommonLib(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRestartableTransaction(qorus_dbg.internals, qpgm, &xsink);

    qorus_Fsm(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusFsmHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusPipelineFactory(qorus_dbg.internals, qpgm, &xsink);

    qorus_qorus(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_shared_system(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_wf_core_system(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_wf_system(qorus_dbg.internals, qpgm, &xsink);
    qorus_misc(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_common_master_core_client(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_cluster_common_server_api(qorus_dbg.internals, qpgm, &xsink);

    qpgm->parseCommit(&xsink, &xsink, QORUS_WARN_MASK);

    int rc = 0;
    if (!xsink.isEvent())
        qpgm->runClass("QWf", &xsink);

    qpgm->waitForTerminationAndDeref(&xsink);
    xsink.handleExceptions();

    return rc;
}
