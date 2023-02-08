
import qoremod.DataProvider.AbstractDataProcessor;

import org.qore.jni.Hash;
import org.qore.jni.QoreException;
import org.qore.jni.QoreClosureMarkerImpl;

import qore.OMQ.UserApi.UserApi;
import qore.OMQ.UserApi.Job.JobApi;

import java.util.Map;
import java.util.stream.Collectors;

@SuppressWarnings("deprecation")
class Issue3485JavaProcessor2 extends AbstractDataProcessor {
    Issue3485JavaProcessor2() throws Throwable {
    }

    protected void submitImpl(QoreClosureMarkerImpl enqueue, Object data) throws Throwable {
        UserApi.logInfo("Issue3485Processor2 was called: %y", data);
        Hash rec = (Hash)data;
        Map<String, Object> new_rec = rec.entrySet().stream().collect(
            Collectors.toMap(e -> "Issue3485JavaProcessor2-" + e.getKey(), Map.Entry::getValue)
        );
        // can only be used in a job
        JobApi.saveInfo(new_rec);
        enqueue.call(new_rec);
    }

    protected boolean supportsBulkApiImpl() {
        return false;
    }
}
