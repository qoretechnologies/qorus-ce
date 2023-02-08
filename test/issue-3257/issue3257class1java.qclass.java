// name: issue3257class1java
// version: 1.0
// desc: issue 3257 class 1
// author: Qore Technologies, s.r.o.
// requires: issue3257class2java
// lang: java

class issue3257class1java extends issue3257class2java {
    issue3257class1java() throws Throwable {
    }

    protected String test() {
        String test_val = super.test();
        return test_val + "issue3257class1java_";
    }
}
// END
