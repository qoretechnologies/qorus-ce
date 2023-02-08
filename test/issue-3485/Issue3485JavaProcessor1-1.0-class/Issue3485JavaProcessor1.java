
import qoremod.DataProvider.AbstractDataProcessor;

import org.qore.jni.Hash;
import org.qore.jni.QoreException;
import org.qore.jni.QoreClosureMarkerImpl;

import qore.OMQ.UserApi.UserApi;

import java.util.Map;
import java.util.stream.Collectors;

class Issue3485JavaProcessor1 extends AbstractDataProcessor {
    public String pfx;
    public Hash crec;
    public boolean raise_error = false;

    Issue3485JavaProcessor1() throws Throwable {
        pfx = (String)UserApi.getConfigItemValue("pfx");
        crec = (Hash)UserApi.getConfigItemValue("crec");
        raise_error = (Boolean)UserApi.getConfigItemValue("raise_error");
        UserApi.logInfo("Issue3485JavaProcessor1 got config pfx: %y crec: %y raise_error: %y", pfx, crec, raise_error);
    }

    protected void submitImpl(QoreClosureMarkerImpl enqueue, Object data) throws Throwable {
        UserApi.logInfo("Issue3485JavaProcessor1 was called: %y", data);
        if (raise_error) {
            raise_error = false;
            throw new QoreException("ERROR", "error");
        }
        Hash rec;
        if (data == null) {
            rec = new Hash() {
                {
                    put("test1", "one");
                    put("test2", "two");
                }
            };
        } else {
            rec = (Hash)data;
        }
        Map new_rec = rec.entrySet().stream().collect(
            Collectors.toMap(e -> pfx + "-" + e.getKey(), Map.Entry::getValue)
        );
        UserApi.logInfo("1 output: %y", new_rec);
        enqueue.call(new_rec);
    }

    protected boolean supportsBulkApiImpl() {
        return false;
    }
}
