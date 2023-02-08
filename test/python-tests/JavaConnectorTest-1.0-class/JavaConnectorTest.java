import qore.OMQ.UserApi.UserApi;

class JavaConnectorTest {
    static String test(Object input) throws Throwable {
        UserApi.logInfo("got input: %y", input);
        return "java-test";
    }
}
