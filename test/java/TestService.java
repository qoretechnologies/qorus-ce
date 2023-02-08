
import qoremod.QorusInterfaceTest.*;
import qoremod.QorusClientBase.*;
import qoremod.QorusClientBase.OMQ.$Constants;
import qoremod.QorusClientBase.OMQ.Client.QorusSystemRestHelper;

import org.qore.jni.QoreClosureMarkerImpl;

public class TestService extends QorusServiceTest {
    public static void main(String[] args) throws Throwable {
        new TestService(args);
    }

    public TestService(String[] args) throws Throwable {
        super("http-test", "1.0", (Object[])args);

        addTestCase("svc test", new QoreClosureMarkerImpl() {
            public Object call(Object... args) throws Throwable { testService(); return null; }
        });
        main();
    }

    private void testService() throws Throwable {
        CallService call = new CallService("http-test", "echo", 1);
        exec(call);
        assertEq(1, ((Object[])call.getResult())[0]);
    }
}