#!/usr/bin/env qore

%require-our

# here we add fallback paths to the QORE_MODULE_DIR search path,
# in case QORE_MODULE_DIR is not set properly for Qorus
%append-module-path /var/opt/qorus/qlib:$OMQ_DIR/qlib:/opt/qorus/qlib:$OMQ_DIR/user/modules

%requires QorusClientCore

our int $count;   # count of orders created
our int $total;   # total number of orders to create

const opts = (
    "url"    : "url,u=s",
    "threads": "threads,t=i",
    "prio"   : "priority,p=i",
    "sched"  : "schedule,s=i",
    "parent" : "parent,P=i",
    "blocked": "blocked,b",
    "data"   : "d,data=s",
    "help"   : "help,h",
    );

sub usage() {
    printf(
"usage: %s [options] <number> <order>
  -u,--url=arg       sets Qorus server url (ex: http://host:port)
  -t,--threads=arg   repeat action in arg threads
  -p,--priority=arg  set order priority
  -P,--parent=arg    the loosely-coupled parent workflow order id
  -s,--schedule=arg  schedule order arg minutes in the future
  -b,--blocked       create order with status BLOCKED
  -d,--data=arg      create order with the given data
  -h,--help          this help text
", get_script_name());
    exit(1);
}

hash sub process_command_line() {
    my GetOpt $g(opts);
    my hash $o = $g.parse2(\$ARGV);

    if ($o.help)
        usage();

    $o.num = int(shift $ARGV);

    if (!$o.num)
	usage();

    if (!$o.threads)
	$o.threads = 1;

    $o.order = shift $ARGV;

    if (exists $o.data)
	$o.data = QorusClientAPI::parseToQoreValue($o.data);

    return $o;
}

sub do_orders(string $url, string $order, string $ver, hash $o) {
    my QorusSystemAPIHelper $omqapi();
    $omqapi.setURL($url);

    my string $cmd = "omq.system.create-order";

    while (True) {
	my *int $c = $count++;

	if ($c >= $total)
	    break;

	stdout.printf("TID %d: %04d/%04d: creating order: ", gettid(), $c, $total); stdout.sync();
	my hash $h.staticdata = exists $o.data ? $o.data :
	    ( "account" : ( "name" : ( "first" : "Test", "last" : "Customer" ),
			    "address" : ( "street" : "Vitoshka", "number" : 25, "city" : "Sofia", "country" : "BG", "postcode" : "1000" ),
			    "telephone" : "+359878100001",
			    "email" : "test@customer.com",
			    "bulstat" : "0482135" ),
	      "product" : ( "name" : "VIVACOM_TRIO", "start-date" : now() ),
	      "customer-type" : "SOHO",
	    );

	if ($o.sched)
	    $h.scheduled = now() + minutes($o.sched);
	if (exists $o.prio)
	    $h.priority = $o.prio;
	if ($o.parent)
	    $h.parent_workflow_instanceid = $o.parent;
	if ($o.blocked)
	    $h.status = OMQ::StatBlocked;

	if ($order == "SIMPLETEST")
	    $h."order-keys" = ( "key1" : sprintf("%s-%019d", now(), rand()) );

	my hash $rs = $omqapi.callAPI($cmd, $h + ("name": $order, "version": $ver));
	stdout.printf("%d\n", $rs.workflow_instanceid);
    }
}

sub create_orders() {
    # initialize Qorus client library
    qorus_client_init();

    my *hash $options = qorus_parse_options("qorus-client");

    my hash $o = process_command_line();
    if (exists $o.url)
	$omqapi.setURL($o.url);

    my string $order = exists $o.order ? $o.order : "ARRAYTEST";

    my string $ver;
    if (exists $o.order) {
	my int $i = index($order, ":");
	if ($i > 0) {
	    $ver = substr($order, $i + 1);
	    splice $order, $i;
	}
    }

    if (!exists $ver) {
	try
	    $ver = $omqapi."omq.system.service.omqmap.rlookupworkflow"($order).lastversion;
	catch ($ex)
	    $ver = "2.0";
    }

    $total = $o.num;

    printf("creating %d order%s in %d thread%s\n", $o.num, $o.num == 1 ? "" : "s",
	   $o.threads, $o.threads == 1 ? "" : "s");

    #printf("o=%N\n", $o);
    while ($o.threads--)
	background do_orders($omqapi.getURL(), $order, $ver, $o);
}

create_orders();
