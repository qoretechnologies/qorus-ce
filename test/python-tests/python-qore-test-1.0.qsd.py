from svc import QorusService
from qore.__root__ import QoreConnectorTest

class PythonQoreTest(QorusService):
    def __init__(self):
        ####### GENERATED SECTION! DON'T EDIT! ########
        self.class_connections = ClassConnections_PythonQoreTest()
        ############ GENERATED SECTION END ############

    ####### GENERATED SECTION! DON'T EDIT! ########
    def test(self, *params):
        return self.class_connections.Connection_1(*params)
    ############ GENERATED SECTION END ############

####### GENERATED SECTION! DON'T EDIT! ########
class ClassConnections_PythonQoreTest:
    def __init__(self):
        UserApi.startCapturingObjectsFromPython()
        try:
            # map of prefixed class names to class instances
            self.class_map = {
                'QoreConnectorTest': QoreConnectorTest(),
            }
        finally:
            UserApi.stopCapturingObjectsFromPython()

    def callClassWithPrefixMethod(self, prefixed_class, method, *argv):
        UserApi.logDebug("ClassConnections_PythonQoreTest: callClassWithPrefixMethod: method: %s, class: %y", method, prefixed_class)
        return getattr(self.class_map[prefixed_class], method)(*argv)

    def Connection_1(self, *params):
        UserApi.logDebug("Connection_1 called with data: %y", *params)

        UserApi.logDebug("calling test: %y", *params)
        return self.callClassWithPrefixMethod("QoreConnectorTest", "test", *params)
############ GENERATED SECTION END ############
