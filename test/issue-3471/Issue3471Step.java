import qore.OMQ.UserApi.Workflow.QorusNormalStep;

class Issue3471Step extends QorusNormalStep {
    public Issue3471Step() throws Throwable {
        throw new Exception("shouldn't be called when loaded");
    }

    public void primary() throws Throwable {
    }
}
