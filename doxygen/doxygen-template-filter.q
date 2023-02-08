#!/usr/bin/env qore

%include ../lib/qorus-client.ql
#/

%exec-class DoxygenTemplateFilter

%require-our

const opts = (
    "gtag": "g,generate-tag",
    "rtag": "u,use-tags=s",
    "ign": "i,ignore",
    "ver": "q,qorus-version",
    "help": "h,help",
    );

class DoxygenTemplateFilter {
    constructor() {
	my GetOpt $g(opts);
	try {
	    $.o = $g.parse2(\$ARGV);
	}
	catch ($ex) {
	    printf("%s\n", $ex.desc);
	    exit(1);
	}
	if ($.o.help)
	    DoxygenTemplateFilter::usage();

	if ($.o.ver) {
	    printf("%s\n", OMQ::version);
	    exit(0);
        }

	my string $ifn = shift $ARGV;
	my string $ofn = shift $ARGV;
	my string $tagofn = $ofn + ".tag";

	my string $name = sprintf("\"%s\"", shift $ARGV);
	my string $output = shift $ARGV;
	my string $src = shift $ARGV;

	my string $ver = sprintf("\"%s\"", OMQ::version);

	printf("filtering %n -> %n (output dir: %n)\n", $ifn, $ofn, $output);

	my File $if();
	$if.open2($ifn);

	my File $of();
	$of.open2($ofn, O_CREAT | O_WRONLY | O_TRUNC);

	while (exists (my *string $line = $if.readLine())) {
	    $line = regex_subst($line, '\$\{NAME\}', $name);
	    $line = regex_subst($line, '\$\{QORUS_VERSION\}', $ver);
	    $line = regex_subst($line, '\$\{SOURCES\}', $src);
	    $line = regex_subst($line, '\$\{OUTPUT\}', $output);
            $line = regex_subst($line, '\$\{TARGET_SUBDIR\}', sprintf("%s-%s", $output, OMQ::version));

	    if ($.o.gtag)
		$line = regex_subst($line, '(GENERATE_TAGFILE.*=).*$', '$1'+$tagofn);

	    if (exists $.o.rtag)
		$line = regex_subst($line, '(TAGFILES.*=).*$', '$1'+$.o.rtag);

	    if ($.o.ign)
		$line = regex_subst($line, '(HIDE_UNDOC_MEMBERS.*=).*$', '$1YES');
	    $of.print($line);
	}
    }

    static usage() {
      printf("usage: %s [options] <file1> ...
  -g,--generate-tag    generate tag file
  -u,--use-tags=<ARG>  use tag files, ARG='file1=loc1 file2=loc2...'
  -i,--ignore          ignore undocumented members
  -h,--help            this help text
", get_script_name());
      exit(1);
    }

}
