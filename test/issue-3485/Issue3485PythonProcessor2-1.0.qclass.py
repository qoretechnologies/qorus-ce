from qore.DataProvider import AbstractDataProcessor

class Issue3485PythonProcessor2(AbstractDataProcessor):
    def __init__(self):
        super(AbstractDataProcessor, self).__init__()

    def submitImpl(self, enqueue, data):
        UserApi.logInfo("Issue3485Processor2 was called: %y", data)
        new_rec = {("Issue3485PythonProcessor2-" + k): v for k, v in data.items()}
        # can only be used in a job
        jobapi.saveInfo(new_rec)
        enqueue(new_rec)

    def supportsBulkApiImpl(self):
        return False
