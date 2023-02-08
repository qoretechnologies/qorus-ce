#!/usr/bin/env qore
# -*- mode: qore; indent-tabs-mode: nil -*-

%require-our
%include qorus-client.ql

%requires qore >= 0.8

# global variables
our hash $o;

const def_wflist = ( "ARRAYTEST", "SIMPLETEST" );

sub usage() {
    printf(
"usage: %s [options] [workflow-names]
  -u,--url=arg      sets YAML-RPC command url (ex: yamlrpc://host:port)
  -d,--delay=ARG    sleep for ARG seconds between iterations
  -l,--limit=ARG    maximum number of retries to execute per iteration
  -N,--no-loop      exit after 1 iteration
  -v,--verbose      shows more information
  -t,--threads=ARG  execute retries in ARG threads
  -o,--old-api      execute old API for single retries per call
  -h,--help         this help text
", get_script_name());
    exit(1);
}

sub process_command_line() {
    my hash $opts =
        ( "url"     : "u,url=s",
	  "noloop"  : "N,no-loop",
          "verb"    : "v,verbose",
	  "delay"   : "d,delay=i",
	  "limit"   : "l,limit=i",
	  "wf"      : "w,workflow=s@",
	  "threads" : "t,threads=i",
	  "old"     : "o,old-api",
	  "retry"   : "r,retry",
          "help"    : "h,help" );

    my GetOpt $g = new GetOpt($opts);
    $o = $g.parse(\$ARGV);
    if (exists $o{"_ERRORS_"}) {
        printf("%s\n", $o."_ERRORS_"[0]);
        exit(1);
    }
    if ($o.help)
        usage();

    $o.wf = ();
    foreach my string $wf in ($ARGV)
	$o.wf += $wf;

   if (!elements $o.wf)
	$o.wf = def_wflist;

    if (!exists $o.delay)
	$o.delay = 10;

    if (!$o.threads)
	$o.threads = 1;
}

sub strlist(list $l) returns string {
    my $str = "";
    foreach my $e in ($l)
	$str += sprintf("%s ", $e);
    return $str;
}

sub strlist(string $l) returns string {
    return sprintf("%s ", $l);
}

sub getWorkflowID(QorusSystemAPIHelper $qapi, string $wf) returns int {
    my any $ver;
    my int $i = index($wf, ":");
    if ($i > 0) {
	$ver = substr($wf, $i + 1);
	$wf = substr($wf, 0, $i);
    }

    my any $rv = $qrest.get("system/metadata/rlookupworkflow/" + $wf + "/" + $ver);

    if (!exists $rv)
	throw "INVALID-WORKFLOW", sprintf("unknown workflow %s%s", $wf, exists $ver ? sprintf(":%s", $ver) : "");

    my hash $h = !exists $ver ? $rv.($rv.lastversion) : $rv;

    return int($h.workflowid);
}

sub do_retry(Counter $c, list $wfil) {
    on_exit $c.dec();

    my QorusSystemAPIHelper $qapi = new QorusSystemAPIHelper(( "url" : $o.url ));

    if (!$o.old) {
	try {
	    printf("TID %d: retry-workflow-instances %d order%s\n", gettid(), elements $wfil, elements $wfil == 1 ? "" : "s");
	    my bool $lok = False;
	    my hash $h = $qapi."retry-workflow-instances"($wfil);
	    my HashIterator $hi($h);
	    while ($hi.next()) {
		if ($hi.getValue().typeCode() == NT_HASH) {
		    print(".");
		    $lok = True;
		}
		else {
		    if ($lok) {
			$lok = False;
			print("\n");
		    }
	   	    printf("TID %d: retry %d: %s\n", gettid(), $hi.getKey(), $hi.getValue());
		}
	    }
	    if ($lok)
		print("\n");
	    #foreach my string $wfiid in (keys $h)
		#printf("TID %d: retry %d: %s\n", gettid(), $wfiid, type($h.$wfiid) == Type::String ? $h.$wfiid : "OK");
	}
	catch ($ex) {
	    printf("%s:%d: %s: %s\n", $ex.file, $ex.line, $ex.err, $ex.desc);
	}
	return;
    }

    while (elements $wfil) {
	my any $e = shift $wfil;
	do_workflow_retry($qapi, $e);
    }
}

sub do_workflow_retry(QorusSystemAPIHelper $qapi, $wfi) {
    printf("retry %d: ", $wfi);
    try {
	my hash $rs = $qapi."retry-workflow-instance"($wfi);
	printf("OK\n", $rs.segments_updated);
    }
    catch ($ex)
	printf("%s\n", $ex.desc);
}

sub get_error_list_intern(QorusSystemAPIHelper $qapi, string $ver, $ids) returns list {
    # make simple call if qorus is version 2 or higher
    my list $l = list("ERROR");
    if ($o.retry)
        $l += "RETRY";
    if ($ver[0] >= 2) {
	my any $rc = $qapi."omq.system.service.info.getWorkflowInstanceList"($ids, 1970-01-01, $l, 9999999);
	return exists $rc ? $rc : ();
    }

    # have to call once for each element
    my list $wfil = ();
    foreach my $id in ($ids)
	$wfil += $qapi."omq.system.service.info.getWorkflowInstanceList"($id, 1970-01-01, $l, 9999999);

    return $wfil;
}

sub get_error_list(QorusSystemAPIHelper $qapi, string $ver, $ids) returns list {
    my list $wfil = get_error_list_intern($qapi, $ver, $ids);
    if ($o.limit)
	splice $wfil, $o.limit;

    return $wfil;
}

sub retry() {
    my QorusSystemAPIHelper $qapi = new QorusSystemAPIHelper(( "url" : $o.url ));

    # get workflow IDs
    my list $wfids;
    foreach my $wf in ($o.wf)
	$wfids += getWorkflowID($qapi, $wf);

    # get server version
    my $ver = $qapi."get-status"."omq-version";

    #printf("ids=%N\n",$wfids);

    while (True) {
        my list $wfil = get_error_list($qapi, $ver, $wfids);

	printf("%d workflow_instance%s with status ERROR%s\n", elements $wfil, elements $wfil == 1 ? "" : "s", $o.retry ? " or RETRY" : "");

	my Counter $c();
	my int $t = $o.threads;
	my int $elems = elements $wfil / $o.threads + 1;
	while ($t-- && elements $wfil) {
	    #printf("elements $wfil: %d\n", elements $wfil);
	    my $l = extract $wfil, 0, $elems;
	    $c.inc();
	    background do_retry($c, $l);
	}

	$c.waitForZero();

	my string $cmd = sprintf("oview -ca %s", strlist($o.wf));
	#printf("%s\n", $cmd);
	system($cmd);
	if ($o.noloop)
	    break;
	printf("sleeping for %d seconds\n", $o.delay);
	sleep($o.delay);
    }
}

sub main() {
    qorus_client_init();
    my hash $options = qorus_parse_options("qorus-client");

    process_command_line();

    if (!exists $o.url)
        $o.url = $options."client-url";

    retry();
}

main();
