CLASSPATH=${OMQ_DIR}/jar/qore-jni.jar
CLASSLOADER_ARG=-Djava.system.class.loader=org.qore.jni.QoreURLClassLoader

all: TestWorkflow.class TestService.class TestJob.class

TestWorkflow.class TestWorkflow$$1.class TestWorkflow$$2.class TestWorkflow$$2$$1.class: TestWorkflow.java
	qjavac -cp ${CLASSPATH} $<

TestService.class TestService$$1.class: TestService.java
	qjavac -cp ${CLASSPATH} $<

TestJob.class TestJob$$1: TestJob.java
	qjavac -cp ${CLASSPATH} $<

run: run-wf run-svc run-job

run-wf:
	java -cp ${CLASSPATH}:. ${CLASSLOADER_ARG} TestWorkflow -vv

run-svc:
	java -cp ${CLASSPATH}:. ${CLASSLOADER_ARG} TestService -vv

run-job:
	java -cp ${CLASSPATH}:. ${CLASSLOADER_ARG} TestJob -vv
