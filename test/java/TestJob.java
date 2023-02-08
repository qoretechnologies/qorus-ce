

import qoremod.QorusInterfaceTest.*;
import qoremod.QorusClientBase.*;
import qoremod.QorusClientBase.OMQ.$Constants;
import qoremod.QorusClientBase.OMQ.Client.QorusSystemRestHelper;

import org.qore.jni.QoreClosureMarkerImpl;

public class TestJob extends QorusJobTest {
    public static void main(String[] args) throws Throwable {
        new TestJob(args);
    }

    public TestJob(String[] args) throws Throwable {
        super("test", "1.0", args);

        addTestCase("job test", new QoreClosureMarkerImpl() {
            public Object call(Object... args) throws Throwable { testJob(); return null; }
        });
        main();
    }

    private void testJob() throws Throwable {
        Action action = new RunJobResult(qoremod.QorusClientBase.OMQ.$Constants.StatComplete);
        exec(action);
    }
}