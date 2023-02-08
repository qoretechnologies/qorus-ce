package com.qoretechnologies.qorus.test.regression;

import qore.OMQ.UserApi.UserApi;

public class issue3102javaclass {
    public static void assertEq(Object expects, Object actual) throws Throwable {
        UserApi.logInfo("%s: testing assertion", getSourceLocation());
        if (!equal(expects, actual)) {
            throw new Exception(String.format("expected %s; got %s",
                expects == null ? "null" : expects.toString(),
                actual == null ? "null" : actual.toString()));
        }
        UserApi.logInfo("%s: assertion OK", getSourceLocation());
    }

    public static void assertTrue(boolean b) throws Throwable {
        if (!b) {
            throw new Exception("expected true; got false");
        }
        UserApi.logInfo("%s: assertion OK", getSourceLocation());
    }

    public static void assertFalse(boolean b) throws Throwable {
        if (b) {
            throw new Exception("expected false; got true");
        }
        UserApi.logInfo("%s: assertion OK", getSourceLocation());
    }

    public static void assertNull(Object o) throws Throwable {
        if (o != null) {
            throw new Exception(String.format("expected null; got %s", o.toString()));
        }
        UserApi.logInfo("%s: assertion OK", getSourceLocation());
    }

    public static String getSourceLocation() {
        return getSourceLocation(4);
    }

    public static String getSourceLocation(int stack_offset) {
        String fullClassName = Thread.currentThread().getStackTrace()[stack_offset].getClassName();
        String className = fullClassName.substring(fullClassName.lastIndexOf(".") + 1);
        String methodName = Thread.currentThread().getStackTrace()[stack_offset].getMethodName();
        int lineNumber = Thread.currentThread().getStackTrace()[stack_offset].getLineNumber();

        return String.format("%s.%s():%d", className, methodName, lineNumber);
    }

    public static boolean equal(Object expects, Object actual) {
        if (expects == null) {
            return actual == null;
        }
        if (actual == null) {
            return false;
        }
        return expects.equals(actual);
    }
}
