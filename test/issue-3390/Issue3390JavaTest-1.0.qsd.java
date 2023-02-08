
import qore.OMQ.UserApi.UserApi;
import qore.OMQ.UserApi.Service.QorusService;

import com.qoretechnologies.qorus.test.regression.JavaTest;
import org.qore.lang.reflection.Type;

class Issue3390JavaTest extends QorusService {
    Issue3390JavaTest() throws Throwable {
    }

    @SuppressWarnings("deprecation")
    public String test() throws Throwable {
        try {
            UserApi.stopCapturingObjectsFromJava();
            UserApi.clearObjectCache();
            Type type0 = new Type("string");
            JavaTest.assertEq(0L, UserApi.getObjectCacheSize());
            JavaTest.assertEq(true, UserApi.checkObjectCache(type0.getQoreObject()) == null);
            UserApi.startCapturingObjectsFromJava();
            Type type1 = new Type("string");
            JavaTest.assertEq(1L, UserApi.getObjectCacheSize());
            JavaTest.assertEq(true, UserApi.checkObjectCache(type1.getQoreObject()) != null);
            return "OK";
        } finally {
            UserApi.stopCapturingObjectsFromJava();
        }
    }
}
