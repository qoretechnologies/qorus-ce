from qore.DataProvider import AbstractDataProcessor

class Issue3485PythonProcessor1(AbstractDataProcessor):
    def __init__(self):
        super(AbstractDataProcessor, self).__init__()
        self.pfx = UserApi.getConfigItemValue("pfx")
        self.crec = UserApi.getConfigItemValue("crec")
        self.raise_error = UserApi.getConfigItemValue("raise_error")
        UserApi.logInfo("Issue3485PythonProcessor1 got config pfx: %y crec: %y raise_error: %y", self.pfx, self.crec, self.raise_error)

    def submitImpl(self, enqueue, data):
        UserApi.logInfo("Issue3485PythonProcessor1 was called: %y", data)
        if (self.raise_error):
            self.raise_error = False
            raise QoreException("ERROR", "error")

        if data:
            rec = data
        else:
            rec = {
                "test1": "one",
                "test2": "two",
            }

        new_rec = {(self.pfx + "-" + k): v for k, v in rec.items()}
        UserApi.logInfo("1 output: %y", new_rec)
        enqueue(new_rec)

    def supportsBulkApiImpl(self):
        return False
