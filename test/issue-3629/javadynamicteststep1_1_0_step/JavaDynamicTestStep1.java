import qore.OMQ.*;
import qore.OMQ.UserApi.*;
import qore.OMQ.UserApi.Workflow.*;
import qore.OMQ.UserApi.Workflow.QorusNormalStep;

import org.qore.jni.Hash;

class JavaDynamicTestStep1 extends QorusNormalStep {
    JavaDynamicTestStep1() throws Throwable {
        super();
    }

    public void primary() throws Throwable {
        updateDynamicData(new Hash() {
            {
                put("test", "test from java");
            }
        });
    }
}
