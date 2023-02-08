from svc import QorusService
from qore.WebSocketHandler import WebSocketHandler, WebSocketConnection
from qore.json import make_json
from datetime import timedelta

quit = False
ExitPollInterval = timedelta(seconds = 1)

class MyWebSocketConnection(WebSocketConnection):
    def __init__(self, handler):
        super(MyWebSocketConnection, self).__init__(handler)

    def gotMessage(self, msg):
        UserApi.logInfo("got msg: %y", msg)
        self.send("echo " + msg)

class MyWebSocketHandler(OMQ.AbstractServiceWebSocketHandler):
    def __init__(self):
        super(MyWebSocketHandler, self).__init__("my-websocket")
        svcapi.startThread(self.eventListener)

    def eventListener(self):
        global quit
        global ExitPollInterval
        min_id = 1
        while not quit:
            eh = svcapi.waitForEvents(min_id, ExitPollInterval)
            if 'shutdown' in eh:
                UserApi.logInfo("system is shutting down; stopping event thread")
                break
            min_id = eh['lastid'] + 1
            if not 'events' in eh:
                self.sendAll('"timeout"')
                continue
            json = make_json(eh['events'])
            self.sendAll(json)

    def getConnectionImpl(self, cx, hdr, cid):
        return MyWebSocketConnection(self)

class PythonWebSocketTest(QorusService):
    # "init" is a registered service method in the corresponding YAML metadata file
    def init(self):
        svcapi.bindHttp(MyWebSocketHandler())

    # "stop" is a registered service method in the corresponding YAML metadata file
    def stop(self):
        global quit
        quit = True
