#!/usr/bin/env qore
# -*- mode: qore; indent-tabs-mode: nil -*-

%require-our
%enable-all-warnings

%include qorus-client.ql

%requires qore >= 0.8

const default_wsdl = "http://localhost:8001/SOAP/simple?wsdl";

const opts = (
    "verbose" : "verbose,v",
    "wsdl"    : "wsdl,w=s",
    "url"     : "url,u=s",
    "help"    : "help,h"
    );

sub usage() {
    printf("usage: %s [options]
 -u,--url=<ARG>    override target URL
 -v,--verbose      show more information
 -w,--wsdl=<ARG>   set URL for WSDL (default %y)
 -h,--help         this help text
", get_script_name(), default_wsdl);
    exit(1);
}

hash sub process_command_line() {
    my GetOpt $g(opts);
    my hash $o = $g.parse3(\$ARGV);
    if ($o.help)
	usage();
    return $o;
}

sub main() {
    my hash $o = process_command_line();

    if (!$o.wsdl)
	$o.wsdl = default_wsdl;

    my $opts.wsdl_file = $o.wsdl;
    if ($o.url)
	$opts.url = $o.url;

    # arguments to the SOAP operation
    my string $tickerSymbol = "QORE";  # serialized to xsd type "string"

    # set up argument hash for SOAP operation "getOutputFile()"
    my $h.GetCompanyInfo.tickerSymbol = $tickerSymbol;
    
    # create the SoapClient object
    my SoapClient $sc($opts);

    my $info;

    # print out verbose technical SOAP information on errors
    on_error printf("info: %N\n", $info);

    # make the SOAP call and retrieve the response
    my $response = $sc.call("getCompanyInfo", $h, \$info);

    # print out technical SOAP call info if the verbose flag was set
    if ($o.verbose)
	printf("info: %N\n", $info);
    
    # print out the response value
    # the output value (string) is returned in the hash key "return"
    printf("getCompanyInfo() response: %y\n", $response);

    delete $info;
    delete $h.GetCompanyLogo;

    $h.SetCompanyLogo = ( "name" : "QORE", "id" : -1 );
    $h.logo = $response.logo;

    $response = $sc.call("setCompanyLogo", $h, \$info);

    # print out technical SOAP call info if the verbose flag was set
    if ($o.verbose)
	printf("info: %N\n", $info);
    
    # print out the response value
    # the output value (string) is returned in the hash key "return"
    printf("SOAP response: %y\n", $response);
}

main();
