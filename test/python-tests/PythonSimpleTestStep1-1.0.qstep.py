from wf import QorusNormalStep
import qoreloader
from qore.__root__ import QoreTest as qt

class PythonSimpleTestStep1(wf.QorusNormalStep):
    def primary(self):
        UserApi.logInfo("hello from Python")
        qt.assertEq(True, True)
