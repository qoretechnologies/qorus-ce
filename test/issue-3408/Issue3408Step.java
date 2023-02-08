import qore.OMQ.UserApi.UserApi;
import qore.OMQ.UserApi.Workflow.QorusNormalStep;


class Issue3408Step extends QorusNormalStep {
    Issue3408Step() throws Throwable {
    }

    public void primary() throws Throwable {
        TestClass tc = new TestClass();
        tc.log();
    }
}

class TestClass {
    public void log() throws Throwable {
        UserApi.logInfo("primary method has been called, TestClass has been created");
    }
}
