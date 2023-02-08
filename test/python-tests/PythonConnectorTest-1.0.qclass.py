class PythonConnectorTest:
    def test(self, input):
        UserApi.logInfo("input data: %y", input)
        return "python-test"

