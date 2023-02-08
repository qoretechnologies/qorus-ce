from svc import QorusService
qoreloader.load_java('JavaConnectorTest')
from qore.__root__.Jni import JavaConnectorTest

class PythonJavaTest(QorusService):
    def __init__(self):
        ####### GENERATED SECTION! DON'T EDIT! ########
        self.class_connections = ClassConnections_PythonJavaTest()
        ############ GENERATED SECTION END ############

    ####### GENERATED SECTION! DON'T EDIT! ########
    def test(self, *params):
        return self.class_connections.Connection_1(*params)
    ############ GENERATED SECTION END ############

####### GENERATED SECTION! DON'T EDIT! ########
class ClassConnections_PythonJavaTest:
    def __init__(self):
        # map of prefixed class names to class instances
        self.class_map = {
            'JavaConnectorTest': JavaConnectorTest(),
        }

    def callClassWithPrefixMethod(self, prefixed_class, method, *argv):
        UserApi.logDebug("ClassConnections_PythonJavaTest: callClassWithPrefixMethod: method: %s, class: %y", method, prefixed_class)
        return getattr(self.class_map[prefixed_class], method)(*argv)

    def Connection_1(self, *params):
        UserApi.logDebug("Connection_1 called with data: %y", *params)

        UserApi.logDebug("calling test: %y", *params)
        return self.callClassWithPrefixMethod("JavaConnectorTest", "test", *params)
############ GENERATED SECTION END ############
