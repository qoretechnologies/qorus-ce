import qore.OMQ.UserApi.UserApi;
import qore.OMQ.UserApi.Workflow.QorusNormalStep;
import qore.OMQ.UserApi.Workflow.WorkflowApi;

import qore.OMQ.Observer;
import qore.OMQ.Observable;

import org.qore.jni.Hash;

import java.util.Map;

class Issue3420Step extends QorusNormalStep {
    private Issue3420StepTest testClass;
    private Issue3420Observer observer;

    public Issue3420Step() throws Throwable {
        observer = new Issue3420Observer();
        testClass = new Issue3420StepTest();
        testClass.registerObserver(observer);
    }

    public void primary() throws Throwable {
        UserApi.logInfo("primary method has been called");
        testClass.notifyObservers("Issue3420Step::primary", (Hash)getStaticData());
    }
}

class Issue3420Observer extends Observer {
    Issue3420Observer() throws Throwable {
    }

    public void update(String id, Hash data) throws Throwable {
        if (id.equals("Issue3420Step::primary")) {
            UserApi.logInfo("observer notified: %y", data);
            WorkflowApi.updateDynamicData(new Hash() {
                {
                    put("key", data.get("key"));
                }
            });
        } else {
            UserApi.logInfo("ignoring message with id %y (%y)", id, data);
        }
    }
}

class Issue3420StepTest extends Observable {
    public Issue3420StepTest() throws Throwable {
    }
}
