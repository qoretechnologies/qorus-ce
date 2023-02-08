#!/usr/bin/env python3

# import Python's sys module
import sys

# the "qoreloader" module is provided by Qorus and provides the bridge between Python <-> Qore and, with Qore's "jni"
# module, between Python <-> Java
# reference: https://qoretechnologies.com/manual/qorus/gitlab-docs/develop/python/python/html/index.html#python_qoreloader_module
import qoreloader

# the "qoreloader" module provides the magic package "qore" which allows us to import Qore APIs and use them as if
# they were Python APIs
# reference: https://qoretechnologies.com/manual/qorus/gitlab-docs/develop/python/python/html/index.html#python_qoreloader_import_qore
from qore.QUnit import Test

# import Qorus's "QorusClient" class
from qore.QorusClientBase import QorusClient

# import Qorus's "QorusSystemRestHelper" class
from qore.__root__.OMQ.Client import QorusSystemRestHelper

# we inherit the Test class
class MyTest(Test):
    # static class variable
    qrest: QorusSystemRestHelper = QorusSystemRestHelper()

    # initialize the new object
    def __init__(self):
        # call the parent class's constructor
        super(Test, self).__init__("native Python test", "1.0", sys.argv[1:])
        # add test cases
        self.addTestCase("test", self.test)
        # execute the tests
        self.main()

    def test(self):
        pid: int = MyTest.qrest.get("system/pid")
        self.assertGt(0, pid)

# run the test by instantiating the class
MyTest()
