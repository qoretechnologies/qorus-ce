
import qore.OMQ.UserApi.Job.QorusJob;
import qore.OMQ.UserApi.Job.JobApi;

import org.qore.jni.Hash;

class JavaDynamicJobTest extends QorusJob {
    JavaDynamicJobTest() throws Throwable {
        super();
    }

    public void run() throws Throwable {
        logInfo("in run() method");
        Hash info = new Hash() {
            {
                put("test", "test from java");
            }
        };
        saveInfo(info);
        logInfo("saved: %y", info);
    }
}
