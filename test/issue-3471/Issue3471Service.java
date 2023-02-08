
import qore.OMQ.UserApi.Service.QorusService;

class Issue3471Service extends QorusService {
    public Issue3471Service() throws Throwable {
        throw new Exception("shouldn't be called when loaded");
    }

    public void init() throws Throwable {
    }
}
