
import qore.OMQ.UserApi.Job.QorusJob;

class Issue3471Job extends QorusJob {
    public Issue3471Job() throws Throwable {
        throw new Exception("shouldn't be called when loaded");
    }

    public void run() throws Throwable {
    }
}
