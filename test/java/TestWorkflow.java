
import qoremod.QorusInterfaceTest.*;
import qoremod.QorusClientBase.*;
import qoremod.QorusClientBase.OMQ.$Constants;
import qoremod.QorusClientBase.OMQ.Client.QorusLocalRestHelper;

import org.qore.jni.Hash;
import org.qore.jni.QoreClosureMarkerImpl;

public class TestWorkflow extends QorusWorkflowTest {
    public static void main(String[] args) throws Throwable {
        new TestWorkflow(args);
    }

    public TestWorkflow(String[] args) throws Throwable {
        super("SIMPLETEST", "1.0", args);

        addTestCase("wf test", new QoreClosureMarkerImpl() {
            public Object call(Object... args) throws Throwable { testWorkflow(); return null; }
        });

        main();
    }

    @SuppressWarnings("unchecked")
    private void testWorkflow() throws Throwable {
        QorusLocalRestHelper qrest = new QorusLocalRestHelper();
        // turn off error generation for SIMPLETEST workflow
        qrest.put("workflows/SIMPLETEST/setOptions", new Hash() {
            {
                put("options", new Hash() {
                    {
                        put("no-errors", true);
                        put("fast-exec", true);
                        put("no-init-error", true);
                        put("throw-error", false);
                    }
                });
            }
        });

        Hash static_data = new Hash();
        Hash order_hash = new Hash();
        order_hash.put("staticdata", static_data);

        Hash result = execSynchronous(order_hash);
        assertEq(qoremod.QorusClientBase.OMQ.$Constants.StatComplete, result.get("status"));

        QorusClientAPI omqclient = new QorusClientAPI();
        Hash rv = (Hash)qrest.put("workflows/SIMPLETEST/setAutostart?autostart=1");
        try {
            exec(new CheckRunningWorkflow("SIMPLETEST"));

            // create a workflow order
            int wfiid = Integer.parseInt(omqclient.createWorkflowInstanceName("SIMPLETEST", "1.0", null, new Hash()));

            String name = getQorusInstanceName();
            assertTrue(name != null);

            // workaround for bug #2884:
            qrest.put("workflows/SIMPLETEST/reset");

            exec(new WaitForWfiid(wfiid));
            assertEq(qoremod.QorusClientBase.OMQ.$Constants.StatComplete, qrest.get("orders/" + wfiid + "/workflowstatus"));
        } finally {
            qrest.put("workflows/SIMPLETEST/setAutostart?autostart=0");
        }
    }
}
