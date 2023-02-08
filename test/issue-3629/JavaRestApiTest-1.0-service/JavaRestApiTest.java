
import qore.OMQ.UserApi.Service.QorusService;
import qore.OMQ.UserApi.Service.ServiceApi;
import qore.OMQ.AbstractServiceRestHandler;

import org.qore.jni.Hash;

import java.util.Map;

class JavaRestHandler extends AbstractServiceRestHandler {
    public JavaRestHandler() throws Throwable {
        super("java-rest");
    }

    public Hash get(Hash cx, Hash ah) {
        return Hash.of(
            "code", 200,
            "body", "test from java"
        );
    }
}

class JavaRestApiTest extends QorusService {
    public JavaRestApiTest() throws Throwable {
        super();
    }

    public void init() throws Throwable {
        bindHttp(new JavaRestHandler());
    }
}
