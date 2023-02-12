/*
    qorus_core_main.cpp
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

//#include "QC_FastLock.h"
//#include "QC_AutoFastLock.h"
#include "QC_SegmentEventQueue.h"
#include "QC_TimedWorkflowCache.h"
#include "QC_TimedSyncCache.h"
#include "QC_OrderExpiryCache.h"
#include "QC_PerformanceCache.h"
#include "QC_PerformanceCacheManager.h"

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

void qorus_AsyncQueueManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ControlBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Control(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
//void qorus_Debug(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_FtpServer(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractFtpHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteFtpHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractServiceHttpHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_InstanceData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Orders(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_OrderData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_OrderInstanceNotes(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_SegmentManagerBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_SegmentManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WorkflowUniqueKeyHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WFEntry(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WFEntryCache(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_StepDataHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_TempDataHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_DynamicDataHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_SensitiveDataHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

void qorus_LoggerController(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServiceManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusService(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusCoreService(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_LocalQorusService(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Service(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteQorusService(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteServiceRestHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteServiceSoapHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteServiceWebSocketHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteServiceStream(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractServiceResource(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_SoapServiceResource(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_HttpUserServiceResource(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_FtpServiceResource(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractHttpServiceResourceBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractHttpServiceResource(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_HttpListenerServiceResource(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_HttpSoapListenerServiceResource(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_HttpGlobalHandlerServiceResource(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusUiExtensionResource(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusStreamHandlerResource(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServiceTemplateManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ErrorStreamHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServiceResourceHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServiceThreadContextHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSystemUiExtensionHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_DefaultQorusRBACAuthenticator(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServiceResources(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteHandlerBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteRestStreamRequestHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteHttpRequestHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteExtensionHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteServiceAuthenticator(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteRestSchemaValidator(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteSoapServiceAuthenticator(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteFtpServiceAuthenticator(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemotePersistentDataHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusAbstractApiManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusHttpApiManagementHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSwaggerApiManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSoapApiManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRestApiManagementHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractServiceEventObserver(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServiceEventMethodObserver(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServiceEventFsmObserver(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

void qorus_Session(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServerSessionBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_CoreServerSession(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractWorkflowExecutionInstance(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractCoreWorkflowExecutionInstance(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteWorkflowExecutionInstance(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WorkflowExecutionInstance(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_CoreWorkflowExecutionInstance(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ClusterWorkflowRestartState(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ThreadLocalData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Map(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Workflow(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractWorkflowQueue(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WorkflowQueueBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WorkflowQueue(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteWorkflowQueue(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRestApiHandlerPublic(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRestApiHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRestApiHandlerV2(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRestApiHandlerV3(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRestApiHandlerV4(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRestApiHandlerV5(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRestApiHandlerV6(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRestApiHandlerV7(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusCreatorRestApiHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_GrafanaReverseProxy(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_CommonInterfaceBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ObserverPattern(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusLocalRestHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusOptionsBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusOptions(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
//void qorus_License(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RBAC(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_SQLInterface(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServerSQLInterface(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusEventManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_SyncEventManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSystemRestHelperBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSystemAPIHelperBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMethodGateHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusServiceHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRemoteServiceHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSystemAPI(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusJob(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusCoreJob(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_LocalQorusJob(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Job(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteQorusJob(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_JobManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_CronTimer(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_JobApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusJob(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AuditLocal(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Audit(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ErrorManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServerErrorManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AlertManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Connections(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ConnectionsServer(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Mappers(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMappers(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServerMapperContainer(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_OmqMap(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMapManagerBase(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMapManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AtomicClassActionHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Streams(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractDatasourceManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_DatasourceManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
//void qorus_QorusOracleDatasourcePool(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_Props(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusHttpServer(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusWebDavHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusDebugLogger(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusDebugProgramSource(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusDebugHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WorkflowStatusData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractSegmentWorkflowData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractCoreSegmentWorkflowData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_LocalSegmentWorkflowData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_SegmentWorkflowData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteSegmentWorkflowData(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusUserConnections(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteMonitor(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_DatasourceConnection(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ConnectionDependencyManager(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ActionReason(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_CodeActionReason(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WorkflowOrderStats(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_SchemaSnapshots(bool qorus_dbg_internals, QoreProgram *qpgm, ExceptionSink*xsink);
void qorus_QorusConfigurationItemProvider(bool qorus_dbg_internals, QoreProgram *qpgm, ExceptionSink* xsink);
void qorus_FSA(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ProcessFSA(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteDevelopmentHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_DeployProcessFSA(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_DeleteProcessFSA(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ReleaseProcessFSA(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_TestProcessFSA(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QoreTestProcessFSA(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_PythonTestProcessFSA(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_JavaTestProcessFSA(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_JavaCompileProcessFSA(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QoreSchemaProcessFSA(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_DeployRestClass(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_DeleteRestClass(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ReleaseRestClass(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_TestRestClass(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteDevelopmentRestClass(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_MetricsRestClass(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_FileUploadProcessFSA(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteDevelopment(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_RemoteDevelopmentOptionHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_InterfaceContextHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMasterCoreQsvcCommon(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusIndependentProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRawRemoteFileRequestHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRemoteWebSocketHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusCreatorWebSocketHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

void qorus_Fsm(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusFsmHandler(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusPipelineFactory(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

void qorus_UserApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_MapperApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_ServiceApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusService(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusPluginService(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSystemService(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_WorkflowApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
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
void qorus_QorusCommonLib(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusRestartableTransaction(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

//void qorus_qorus_secret_keys(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_misc(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_common_master_core_client(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_system(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_shared_system(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_wf_core_system(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_svc_core_system(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_logger(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_version(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_common_server_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_job_core_system(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

// cluster support
void qorus_AbstractQorusDistributedProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusClusterApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusMasterClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QdspClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QwfClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QsvcClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QjobClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractLogger(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusSharedApi(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_dsp_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_wf_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_svc_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_job_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_master_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_cpc_core_api(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusClientProcess(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_AbstractQorusClient(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_NetworkKeyHelper(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_QorusParametrizedAuthenticator(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);
void qorus_qorus_core(bool qorus_dbg_internals, QoreProgram* qpgm, ExceptionSink* xsink);

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

const char* optional_load_first_modules[] = {
    "openldap",
};

#define NUM_OPT_MODULES (sizeof(optional_load_first_modules) / sizeof(char*))

const char* req_modules[] = {
    "json",
    "process",
    "reflection",
    "ssh2",
    "sysconf",
    "uuid",
    "xml",
    "yaml",
    "zmq",
    "AwsRestClient",
    "BulkSqlUtil",
    "ConnectionProvider",
    "CsvUtil",
    "DataStreamClient",
    "DataStreamRequestHandler",
    "DataStreamUtil",
    "DbDataProvider",
    "DebugUtil",
    "DebugProgramControl",
    "DebugHandler",
    "FileLocationHandler",
    "FsUtil",
    "HttpServer",
    "HttpServerUtil",
    "JsonRpcConnection",
    "JsonRpcHandler",
    "Logger",
    "MailMessage",
    "Mapper",
    "Mime",
    "MysqlSqlUtil",
    "RestHandler",
    "OracleSqlUtil",
    "PgsqlSqlUtil",
    "Pop3Client",
    "Qorize",
    "Qyaml",
    "RestClient",
    "SalesforceRestClient",
    "Sap4HanaRestClient",
    "SewioRestClient",
    "SewioWebSocketClient",
    "SmtpClient",
    "SoapClient",
    "SoapHandler",
    "SqlUtil",
    "Ssh2Connections",
    "Swagger",
    "TableMapper",
    "TelnetClient",
    "Util",
    "WebDavHandler",
    "WebSocketClient",
    "WebSocketHandler",
    "WebSocketUtil",
    "WebUtil",
    "WSDL",
    "XmlRpcConnection",
    "XmlRpcHandler",
    "YamlRpcClient",
    "YamlRpcHandler",
    "ZeyosRestClient",
};

#define NUM_REQ_MODULES (sizeof(req_modules) / sizeof(char*))

static int my_load_mod(const char* name, QoreProgram* qpgm) {
    SimpleRefHolder<QoreStringNode> err(MM.parseLoadModule(name, qpgm));
    if (err) {
        fprintf(stderr, "ERROR: cannot load required module '%s': %s\n", name, err->c_str());
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
    if (qore_version_major < 1 && qore_version_minor < 9) {
        fprintf(stderr, "ERROR: incompatible qore library: >= 1.9 required, got %s instead, cannot start Qorus\n",
            qore_version_string);
        exit(1);
    }

    // add custom module directories (must be before qore_init())
    qorus_setup_module_paths(argv[0]);

    // add standard module directories afterwards
    MM.addStandardModulePaths();

    // parse options for Qorus itself
    int64 po = PO_REQUIRE_OUR | PO_NEW_STYLE | PO_REQUIRE_PROTOTYPES | PO_ALLOW_WEAK_REFERENCES;
    bool has_compat_permissive_api = false;
    bool compat_permissive_api = false;

    bool has_minimum_tls_13 = false;
    bool minimum_tls_13 = false;

    // first parse the command line
    for (int i = 1; i < argc; ++i) {
        char* p = strchr(argv[i], '=');
        if (!p)
            continue;
        if (!strncmp(argv[i], "compat-permissive-api", 21)) {
            has_compat_permissive_api = true;
            compat_permissive_api = q_parse_bool(++p);

            //printd(5, "compat-permissive-api: %s\n", compat_permissive_api ? "true" : "false");
            continue;
        }
        if (!strncmp(argv[i], "minimum-tls-13", 14)) {
            has_minimum_tls_13 = true;
            minimum_tls_13 = q_parse_bool(++p);

            //printd(5, "minimum_tls_13: %s\n", minimum_tls_13 ? "true" : "false");
            continue;
        }
        // ignore all other options
    }

    // parse command line options that need to take effect before parsing Qorus
    qorus_dbg_t qorus_dbg = qorus_parse_options(argc, argv, po, {
        {"qorus.compat-permissive-api",
            [has_compat_permissive_api, &compat_permissive_api] (const std::string& val, int64& po) mutable -> void {
                if (!has_compat_permissive_api) {
                    compat_permissive_api = q_parse_bool(val.c_str());
                }
            }
        },
        {"qorus.minimum-tls-13",
            [has_minimum_tls_13, &minimum_tls_13] (const std::string& val, int64& po) mutable -> void {
                printf("parsing %s: has: %d m: %d\n", val.c_str(), has_minimum_tls_13, q_parse_bool(val.c_str()));
                if (!has_minimum_tls_13) {
                    minimum_tls_13 = q_parse_bool(val.c_str());
                }
            }
        },
    });

    int qore_lib_opts = QORE_OPTS;
    if (minimum_tls_13) {
        qore_lib_opts |= QLO_MINIMUM_TLS_13;
    }

    if (!compat_permissive_api) {
        po |= PO_STRICT_ARGS | PO_REQUIRE_TYPES;
    }

    // initialize Qore subsystem
    qore_init(QORUS_LICENSE, "UTF-8", true, qore_lib_opts);

    // cleanup Qore subsystem on exit (deallocate memory, etc)
    ON_BLOCK_EXIT(qore_cleanup);

    // setup the command line
    qore_setup_argv(1, argc, argv);

    QoreProgram* qpgm = new QoreProgram(po);

    // set define for Qorus server
    qpgm->parseDefine("QorusServer", true);
    qpgm->parseDefine("QorusCore", true);
    qpgm->parseDefine("QorusHasIxApis", true);
    qpgm->parseDefine("QorusHasAnyIxApi", true);
    qpgm->parseDefine("QorusHasWfApi", true);
    qpgm->parseDefine("QorusHasSvcApi", true);
    qpgm->parseDefine("QorusHasJobApi", true);
    qpgm->parseDefine("HasJobClass", true);
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

    // load optional modules
    for (unsigned i = 0; i < NUM_OPT_MODULES; ++i) {
        SimpleRefHolder<QoreStringNode> err(MM.parseLoadModule(optional_load_first_modules[i], qpgm));
    }

    // load required module(s)
    for (unsigned i = 0; i < NUM_REQ_MODULES; ++i) {
        if (my_load_mod(req_modules[i], qpgm)) {
            return 1;
        }
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
    qpgm->setScriptPath(argv[0]);

    qorus_init_pgm(*QNS);

    // add custom code
    init_omqlib_functions(*QNS);
    init_omqlib_constants(*QNS);

    //QNS->addSystemClass(initFastLockClass());
    //QNS->addSystemClass(initAutoFastLockClass());
    QNS->addSystemClass(initSegmentEventQueueClass(*QNS));

    // add classes from qpp files
    QNS->addSystemClass(initPerformanceCacheClass(*QNS));
    QNS->addSystemClass(initPerformanceCacheManagerClass(*QNS));
    QNS->addSystemClass(initTimedWorkflowCacheClass(*QNS));
    QNS->addSystemClass(initTimedSyncCacheClass(*QNS));
    QNS->addSystemClass(initOrderExpiryCacheClass(*QNS));

    qpgm->getRootNS()->addInitialNamespace(QNS);

    qorus_LoggerController(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_core(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_system(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_shared_system(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_wf_core_system(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_svc_core_system(qorus_dbg.internals, qpgm, &xsink);
    qorus_AsyncQueueManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_ControlBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_Control(qorus_dbg.internals, qpgm, &xsink);
    //qorus_Debug(qorus_dbg.internals, qpgm, &xsink);
    qorus_FtpServer(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractFtpHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteFtpHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractServiceHttpHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_InstanceData(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusOptionsBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusOptions(qorus_dbg.internals, qpgm, &xsink);
    qorus_misc(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_common_master_core_client(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_logger(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_version(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_common_server_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_qorus_job_core_system(qorus_dbg.internals, qpgm, &xsink);
    qorus_Orders(qorus_dbg.internals, qpgm, &xsink);
    qorus_OrderData(qorus_dbg.internals, qpgm, &xsink);
    qorus_OrderInstanceNotes(qorus_dbg.internals, qpgm, &xsink);
    qorus_SegmentManagerBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_SegmentManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_WorkflowUniqueKeyHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_WFEntry(qorus_dbg.internals, qpgm, &xsink);
    qorus_WFEntryCache(qorus_dbg.internals, qpgm, &xsink);
    qorus_StepDataHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_TempDataHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_DynamicDataHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_SensitiveDataHelper(qorus_dbg.internals, qpgm, &xsink);

    qorus_ServiceManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusService(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusCoreService(qorus_dbg.internals, qpgm, &xsink);
    qorus_LocalQorusService(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteQorusService(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteServiceRestHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteServiceSoapHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteServiceWebSocketHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_Service(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteServiceStream(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractServiceResource(qorus_dbg.internals, qpgm, &xsink);
    qorus_SoapServiceResource(qorus_dbg.internals, qpgm, &xsink);
    qorus_HttpUserServiceResource(qorus_dbg.internals, qpgm, &xsink);
    qorus_FtpServiceResource(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractHttpServiceResourceBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractHttpServiceResource(qorus_dbg.internals, qpgm, &xsink);
    qorus_HttpListenerServiceResource(qorus_dbg.internals, qpgm, &xsink);
    qorus_HttpSoapListenerServiceResource(qorus_dbg.internals, qpgm, &xsink);
    qorus_HttpGlobalHandlerServiceResource(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusUiExtensionResource(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusStreamHandlerResource(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServiceTemplateManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_ErrorStreamHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServiceResourceHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServiceThreadContextHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSystemUiExtensionHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_DefaultQorusRBACAuthenticator(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServiceResources(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteRestStreamRequestHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteHandlerBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteHttpRequestHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteExtensionHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteServiceAuthenticator(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteRestSchemaValidator(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteSoapServiceAuthenticator(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteFtpServiceAuthenticator(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemotePersistentDataHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusAbstractApiManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusHttpApiManagementHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSwaggerApiManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSoapApiManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRestApiManagementHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractServiceEventObserver(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServiceEventMethodObserver(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServiceEventFsmObserver(qorus_dbg.internals, qpgm, &xsink);

    qorus_Session(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServerSessionBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_CoreServerSession(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractWorkflowExecutionInstance(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractCoreWorkflowExecutionInstance(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteWorkflowExecutionInstance(qorus_dbg.internals, qpgm, &xsink);
    qorus_WorkflowExecutionInstance(qorus_dbg.internals, qpgm, &xsink);
    qorus_CoreWorkflowExecutionInstance(qorus_dbg.internals, qpgm, &xsink);
    qorus_ClusterWorkflowRestartState(qorus_dbg.internals, qpgm, &xsink);
    qorus_ThreadLocalData(qorus_dbg.internals, qpgm, &xsink);
    qorus_Map(qorus_dbg.internals, qpgm, &xsink);
    qorus_Workflow(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractWorkflowQueue(qorus_dbg.internals, qpgm, &xsink);
    qorus_WorkflowQueueBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_WorkflowQueue(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteWorkflowQueue(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRestApiHandlerPublic(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRestApiHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRestApiHandlerV2(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRestApiHandlerV3(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRestApiHandlerV4(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRestApiHandlerV5(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRestApiHandlerV6(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRestApiHandlerV7(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusCreatorRestApiHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_GrafanaReverseProxy(qorus_dbg.internals, qpgm, &xsink);
    qorus_CommonInterfaceBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_ObserverPattern(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusLocalRestHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_RBAC(qorus_dbg.internals, qpgm, &xsink);
    qorus_SQLInterface(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServerSQLInterface(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusEventManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_SyncEventManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSystemRestHelperBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSystemAPIHelperBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMethodGateHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusServiceHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRemoteServiceHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSystemAPI(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusJob(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusCoreJob(qorus_dbg.internals, qpgm, &xsink);
    qorus_LocalQorusJob(qorus_dbg.internals, qpgm, &xsink);
    qorus_Job(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteQorusJob(qorus_dbg.internals, qpgm, &xsink);
    qorus_JobManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_CronTimer(qorus_dbg.internals, qpgm, &xsink);
    qorus_JobApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusJob(qorus_dbg.internals, qpgm, &xsink);
    qorus_AuditLocal(qorus_dbg.internals, qpgm, &xsink);
    qorus_Audit(qorus_dbg.internals, qpgm, &xsink);
    qorus_ErrorManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServerErrorManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_AlertManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_Connections(qorus_dbg.internals, qpgm, &xsink);
    qorus_ConnectionsServer(qorus_dbg.internals, qpgm, &xsink);
    qorus_Mappers(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMappers(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServerMapperContainer(qorus_dbg.internals, qpgm, &xsink);
    qorus_OmqMap(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMapManagerBase(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMapManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_AtomicClassActionHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_Streams(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractDatasourceManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_DatasourceManager(qorus_dbg.internals, qpgm, &xsink);
    //qorus_QorusOracleDatasourcePool(qorus_dbg.internals, qpgm, &xsink);
    qorus_Props(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusHttpServer(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusWebDavHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusDebugLogger(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusDebugProgramSource(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusDebugHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_WorkflowStatusData(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractSegmentWorkflowData(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractCoreSegmentWorkflowData(qorus_dbg.internals, qpgm, &xsink);
    qorus_LocalSegmentWorkflowData(qorus_dbg.internals, qpgm, &xsink);
    qorus_SegmentWorkflowData(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteSegmentWorkflowData(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusUserConnections(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteMonitor(qorus_dbg.internals, qpgm, &xsink);
    qorus_DatasourceConnection(qorus_dbg.internals, qpgm, &xsink);
    qorus_ConnectionDependencyManager(qorus_dbg.internals, qpgm, &xsink);
    qorus_ActionReason(qorus_dbg.internals, qpgm, &xsink);
    qorus_CodeActionReason(qorus_dbg.internals, qpgm, &xsink);
    qorus_WorkflowOrderStats(qorus_dbg.internals, qpgm, &xsink);
    qorus_SchemaSnapshots(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusConfigurationItemProvider(qorus_dbg.internals, qpgm, &xsink);
    qorus_FSA(qorus_dbg.internals, qpgm, &xsink);
    qorus_ProcessFSA(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteDevelopmentHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_DeployProcessFSA(qorus_dbg.internals, qpgm, &xsink);
    qorus_DeleteProcessFSA(qorus_dbg.internals, qpgm, &xsink);
    qorus_ReleaseProcessFSA(qorus_dbg.internals, qpgm, &xsink);
    qorus_TestProcessFSA(qorus_dbg.internals, qpgm, &xsink);
    qorus_QoreTestProcessFSA(qorus_dbg.internals, qpgm, &xsink);
    qorus_PythonTestProcessFSA(qorus_dbg.internals, qpgm, &xsink);
    qorus_JavaTestProcessFSA(qorus_dbg.internals, qpgm, &xsink);
    qorus_JavaCompileProcessFSA(qorus_dbg.internals, qpgm, &xsink);
    qorus_QoreSchemaProcessFSA(qorus_dbg.internals, qpgm, &xsink);
    qorus_DeployRestClass(qorus_dbg.internals, qpgm, &xsink);
    qorus_DeleteRestClass(qorus_dbg.internals, qpgm, &xsink);
    qorus_ReleaseRestClass(qorus_dbg.internals, qpgm, &xsink);
    qorus_TestRestClass(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteDevelopmentRestClass(qorus_dbg.internals, qpgm, &xsink);
    qorus_MetricsRestClass(qorus_dbg.internals, qpgm, &xsink);
    qorus_FileUploadProcessFSA(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteDevelopment(qorus_dbg.internals, qpgm, &xsink);
    qorus_RemoteDevelopmentOptionHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_InterfaceContextHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusCommonInterface(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusClientServer(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusDataProviderTypeHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRawRemoteFileRequestHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRemoteWebSocketHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusCreatorWebSocketHandler(qorus_dbg.internals, qpgm, &xsink);

    qorus_Fsm(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusFsmHandler(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusPipelineFactory(qorus_dbg.internals, qpgm, &xsink);

    qorus_UserApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_MapperApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_ServiceApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusService(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusPluginService(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSystemService(qorus_dbg.internals, qpgm, &xsink);
    qorus_WorkflowApi(qorus_dbg.internals, qpgm, &xsink);
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

    // cluster support
    qorus_AbstractQorusDistributedProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusClusterApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMasterClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_QdspClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_QwfClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_QsvcClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_QjobClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractLogger(qorus_dbg.internals, qpgm, &xsink);
    qorus_NetworkKeyHelper(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusSharedApi(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_dsp_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_wf_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_svc_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_job_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_master_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_cpc_core_api(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusClientProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_AbstractQorusClient(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusMasterCoreQsvcCommon(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusIndependentProcess(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusCommonLib(qorus_dbg.internals, qpgm, &xsink);
    qorus_QorusRestartableTransaction(qorus_dbg.internals, qpgm, &xsink);

    qorus_QorusParametrizedAuthenticator(qorus_dbg.internals, qpgm, &xsink);
    qpgm->parseCommit(&xsink, &xsink, QORUS_WARN_MASK);

    int rc = 0;
    if (!xsink.isEvent())
        qpgm->runClass("QorusApp", &xsink);

    qpgm->waitForTerminationAndDeref(&xsink);
    xsink.handleExceptions();

    return rc;
}
