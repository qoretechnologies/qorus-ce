import qore.OMQ.*;
import qore.OMQ.UserApi.*;
import qore.OMQ.UserApi.Service.*;
import org.qore.jni.QoreJavaApi;
import org.qore.jni.QoreObject;
import java.util.Map;
import org.qore.jni.Hash;
import java.lang.reflect.Method;
import java.lang.reflect.InvocationTargetException;
import qore.QoreConnectorTest;

class JavaQoreTest extends QorusService {
    // ==== GENERATED SECTION! DON'T EDIT! ==== //
    ClassConnections_JavaQoreTest classConnections;
    // ======== GENERATED SECTION END ========= //

    public JavaQoreTest() throws Throwable {
        super();
        // ==== GENERATED SECTION! DON'T EDIT! ==== //
        classConnections = new ClassConnections_JavaQoreTest();
        // ======== GENERATED SECTION END ========= //
    }

    // ==== GENERATED SECTION! DON'T EDIT! ==== //
    public Object test(Object params) throws Throwable {
        return classConnections.Connection_1(params);
    }
    // ======== GENERATED SECTION END ========= //
}

// ==== GENERATED SECTION! DON'T EDIT! ==== //
class ClassConnections_JavaQoreTest {
    // map of prefixed class names to class instances
    private final Hash classMap;

    ClassConnections_JavaQoreTest() throws Throwable {
        classMap = new Hash();
        UserApi.startCapturingObjectsFromJava();
        try {
            classMap.put("QoreConnectorTest", QoreJavaApi.newObjectSave("QoreConnectorTest"));
        } finally {
            UserApi.stopCapturingObjectsFromJava();
        }
    }

    Object callClassWithPrefixMethod(final String prefixedClass, final String methodName,
                                     Object params) throws Throwable {
        UserApi.logDebug("ClassConnections_JavaQoreTest: callClassWithPrefixMethod: method: %s class: %y", methodName, prefixedClass);
        final Object object = classMap.get(prefixedClass);

        if (object instanceof QoreObject) {
            QoreObject qoreObject = (QoreObject)object;
            return qoreObject.callMethod(methodName, params);
        } else {
            final Method method = object.getClass().getMethod(methodName, Object.class);
            try {
                return method.invoke(object, params);
            } catch (InvocationTargetException ex) {
                throw ex.getCause();
            }
        }
    }

    public Object Connection_1(Object params) throws Throwable {
        // convert varargs to a single argument if possible
        if (params != null && params.getClass().isArray() && ((Object[])params).length == 1) {
            params = ((Object[])params)[0];
        }
        UserApi.logDebug("Connection_1 called with data: %y", params);

        UserApi.logDebug("calling test: %y", params);
        return callClassWithPrefixMethod("QoreConnectorTest", "test", params);
    }
}
// ======== GENERATED SECTION END ========= //
