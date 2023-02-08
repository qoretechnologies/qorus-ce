// service: issue3257servicejava
// serviceversion: 1.0
// servicedesc: issue 3257 service
// serviceauthor: Qore Technologies, s.r.o.
// define-auth-label: auth=permissive
// classes: issue3257class1java
// class-name: issue3257servicejava
// autostart: false
// lang: java
// ENDSERVICE

class issue3257servicejava extends issue3257class1java {
    issue3257servicejava() throws Throwable {
    }

    // name: myTest
    // desc: method
    String myTest() {
        String test_val = super.test();
        return test_val + "issue3257servicejava";
    }
}
