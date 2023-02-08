from job import QorusJob
from qore.__root__ import QoreTest as qt
from qore.reflection import Type

class PythonObjectCacheTest(QorusJob):
    def run(self):
        try:
            UserApi.stopCapturingObjectsFromPython()
            UserApi.clearObjectCache()
            type0 = Type("string")
            qt.assertEq(0, UserApi.getObjectCacheSize())
            UserApi.startCapturingObjectsFromPython()
            type1 = Type("string")
            qt.assertEq(1, UserApi.getObjectCacheSize())
        finally:
            UserApi.stopCapturingObjectsFromPython()
