// name: JavaUserInteractionTest
// version: 1.0
// desc: Qore test step class
// author: Qore Technologies, s.r.o.
// requires: JavaTest
// lang: java
package com.qoretechnologies.qorus.test.regression.java1;

import qore.OMQ.*;
import qore.OMQ.UserApi.*;
import qore.OMQ.UserApi.Workflow.*;

import org.qore.jni.Hash;

import com.qoretechnologies.qorus.test.regression.JavaTest;

public class JavaUserInteractionTest extends QorusAsyncStep {
    public static final Hash DefaultMetadata = new Hash() {
        {
            put("test", 3L);
        }
    };

    public static final Hash DefaultData = new Hash() {
        {
            put("test", 1L);
        }
    };

    public static final Hash NewData = new Hash() {
        {
            put("test2", 2L);
        }
    };

    JavaUserInteractionTest() throws Throwable {
    }

    public void primary() throws Throwable {
        Hash h = getStepInfo();
        //logInfo("h: %y", h);
        JavaTest.assertTrue((boolean)h.get("user_interaction"));

        // test step metadata
        JavaTest.assertEq(DefaultMetadata, callRestApi("GET", "steps/java-user-interaction-test-1/userdata"));

        Hash stepdata = (Hash)getStepData();
        logInfo("stepdata: %y", stepdata);
        JavaTest.assertEq(DefaultData, stepdata);
        // ensure that the REST order response has the step data when the order is cached
        JavaTest.assertEq(DefaultData, ((Object[])((Hash)((Object[])callRestApi("GET", "orders/" + getWfiid() + "/stepdata/"))[0]).get("data"))[0]);

        updateStepData(NewData);
        stepdata = (Hash)getStepData();

        Hash allData = new Hash(DefaultData);
        allData.putAll(NewData);
        JavaTest.assertEq(allData, stepdata);
        JavaTest.assertEq(allData, ((Object[])((Hash)((Object[])callRestApi("GET", "orders/" + getWfiid() + "/stepdata/"))[0]).get("data"))[0]);

        StepDataHelper sdh = new StepDataHelper();
        JavaTest.assertEq(allData, sdh.get());
        try {
            new StepDataHelper();
        } catch (Throwable e) {
            logInfo("exception: " + e.toString());
        }

        String key = generateUniqueKey();
        logInfo("using key %y", key);
        submitAsyncKey(key);
    }

    public void end(Object end_data) {
    }

    public Hash getDefaultStepData() {
        return DefaultData;
    }

    public Hash getStepMetadata() {
        return DefaultMetadata;
    }
}
// END
