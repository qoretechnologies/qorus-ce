from svc import QorusService
from OMQ import AbstractFtpHandler
import os
from os.path import dirname, basename, exists
from qore.Util import get_random_string
from qore.FsUtil import remove_tree
from qore.__root__.Qore import mkdir_ex

#from datetime import timedelta

dir = ""
rmdir = False
stats = {
    "in": {
        "files": 0,
    }
}

class MyFtpHandler(AbstractFtpHandler):
    def __init__(self, dir):
        super(MyFtpHandler, self).__init__(dir)

    def authReceiveFile(self, cwd, orig, path):
        path += ".tmp"
        UserApi.logInfo("authorizing receipt of file %s -> %s", path, path)
        return path

    def fileReceived(self, path):
        global stats

        stats['in']['files'] += 1
        UserApi.logInfo("received file: dir: %y fn: %y", dirname(path), basename(path))

class PythonFtpTest(QorusService):
    # "init" is a registered service method in the corresponding YAML metadata file
    def init(self):
        global dir
        dir = os.environ['OMQ_DIR'] + "/user/ftp-test" + get_random_string()
        if not exists(dir):
            global rmdir
            mkdir_ex(dir, 0o700, True)
            rmdir = True
        handler = MyFtpHandler(dir)
        handler.addListener(0)
        svcapi.bindFtp(handler)

    # "info" is a registered service method in the corresponding YAML metadata file
    def info(self):
        global stats
        return stats

    # "stop" is a registered service method in the corresponding YAML metadata file
    def stop(self):
        global dir
        global rmdir
        if rmdir:
            svcapi.logInfo("removing FTP tree: %y", dir)
            remove_tree(dir)

    # "port" is a registered service method in the corresponding YAML metadata file
    def port(self):
        res = svcapi.getServiceInfo()['resources']
        for key in (res):
            if res[key]['type'] == "FtpListener" and res[key]['info']['familystr'] == "ipv4":
                return res[key]['info']['port']

        raise QoreException("FTP-ERROR", "cannot determine FTP port")
