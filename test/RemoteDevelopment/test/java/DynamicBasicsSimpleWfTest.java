import qoremod.QorusInterfaceTest.*;
import qoremod.QorusClientBase.*;

import org.qore.jni.QoreClosureMarkerImpl;
import org.qore.jni.Hash;

import java.util.Arrays;

public class DynamicBasicsSimpleWfTest extends QorusWorkflowTest {
    private static final String WorkflowName = "BASICS-SIMPLE-WORKFLOW";

    public static void main(String[] args) throws Throwable {
        new DynamicBasicsSimpleWfTest(args);
    }

    public DynamicBasicsSimpleWfTest(String[] args) throws Throwable {
        super(WorkflowName, "1.0", args);

        addTestCase("wf test", new QoreClosureMarkerImpl() {
            public Object call(Object... args) throws Throwable { mainTest(); return null; }
        });

        main();
    }

    @SuppressWarnings("unchecked")
    private void mainTest() throws Throwable {
        Hash staticData = new Hash() {
            {
                put("test1", "test1");
                put("test2", "test2");
                put("test3", "test3");
            }
        };

        long wfiid = createOrder(staticData);
        exec(new WaitForWfiid(wfiid));
    }
}
