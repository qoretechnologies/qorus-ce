from qore.__root__.Qore import get_stack_size

class PythonSimpleTest(job.QorusJob):
    def run(self):
        UserApi.logInfo("Hello from Python: %y", get_stack_size())
