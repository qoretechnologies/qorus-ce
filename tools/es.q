#!/usr/bin/env qore

%include qorus-client.ql

sub main() {
    my $wf = shift $ARGV;
    if (!strlen($wf))
	$wf = "ARRAYTEST";
    printf("workflow: %n\n", $wf);

    QorusClient::init();

    my any $r = $omqapi."set-option"(("recover_delay": 10, "async_delay": 20));
    printf("set-options: %N\n", $r);
    printf("exec-synchronous-workflow: "); flush();
    $r = $omqapi."exec-synchronous-workflow"(("name": $wf, "orderdata": ("staticdata": "hello")));
    printf("%y\n", $r);
}

main();
