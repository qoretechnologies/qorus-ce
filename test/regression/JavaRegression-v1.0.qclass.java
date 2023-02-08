// name: JavaRegression
// version: 1.0
// desc: Java regression test class
// author: Qore Technologies, s.r.o.
// lang: java
// requires: JavaTest
package com.qoretechnologies.qorus.test.regression;

// Qorus imports
import qore.OMQ.UserApi.UserApi;

// Qore imports
import qore.Qore.SQL.AbstractDatasource;
import qore.SqlUtil.AbstractTable;
import qore.Mapper.Mapper;

// Qore JNI imports
import org.qore.jni.Hash;

public class JavaRegression {
    public static void testSchema() throws Throwable {
        Mapper mapper = UserApi.getMapper("java-test-mapper");
        UserApi.logInfo("java mapper class %y", mapper.className());

        try {
            AbstractDatasource omquser = UserApi.getDatasourcePool("omquser");
            try {
                AbstractTable table = UserApi.getSqlTable(omquser, "regression_example");
                try {
                    Hash[] rows = (Hash[])table.selectRows();
                    UserApi.logInfo("java rows: %y", (Object)rows);
                    Hash[] new_rows = (Hash[])mapper.mapAll(rows);
                    UserApi.logInfo("java mapper rows: %y", (Object)new_rows);
                } finally {
                    table.release();
                }
            } finally {
                omquser.release();
            }
        } finally {
            mapper.release();
        }
    }
}
// END
