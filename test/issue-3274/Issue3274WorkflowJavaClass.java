
import qore.OMQ.UserApi.Workflow.QorusWorkflow;

import org.qore.jni.Hash;

class Issue3274WorkflowJavaClass extends QorusWorkflow {
    Issue3274WorkflowJavaClass() throws Throwable {
    }

    @Override
    public void oneTimeInit() throws Throwable {
        logInfo("Issue3274WorkflowClass::oneTimeInit is called");
    }

    @Override
    public void errorHandler(String errcode, Hash errinfo, Object opt) throws Throwable {
        logInfo("Issue3274WorkflowClass::errorHandler is called");
    }

    @Override
    public void detach(String status, String external_order_instanceid) throws Throwable {
        logInfo("Issue3274WorkflowClass::detach is called");
    }

    @Override
    public void attach() throws Throwable {
        logInfo("Issue3274WorkflowClass::attach is called");
    }
}
