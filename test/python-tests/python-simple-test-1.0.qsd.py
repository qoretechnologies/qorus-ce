from svc import QorusService

class PythonSimpleTest(QorusService):
    def test(self, arg):
        UserApi.logInfo("Hello from Python")
        return arg
