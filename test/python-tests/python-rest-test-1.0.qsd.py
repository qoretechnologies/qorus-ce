from svc import QorusService
from qore.RestHandler import AbstractRestClass, RestHandler

class TestRestClass(AbstractRestClass):
    def name(self):
        return "subclass"

    def get(self, cx, ah):
        return RestHandler.makeResponse(200, ah['echo'])

class MyRestHandler(OMQ.AbstractServiceRestHandler):
    def __init__(self):
        super(MyRestHandler, self).__init__("python-rest-test", False, OMQ.PermissiveAuthenticator())
        self.addClass(TestRestClass())

    def put(self, cx, ah):
        UserApi.logInfo("put: %y", ah)
        return {
            'code': 200,
            'body': ah,
        }

class PythonRestTest(QorusService):
    def init(self):
        svcapi.bindHttp(MyRestHandler())
