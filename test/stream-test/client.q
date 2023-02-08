%new-style
%requires QorusClientCore

qorus_client_init2();

FsRemoteSend fs("test", "/tmp/qorus-client-stream.txt");
fs.append("lorem ipsum\n");


