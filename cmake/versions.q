%include ../lib/qorus-version.ql

%new-style
%strict-args
%require-types
%enable-all-warnings

const MAP = {
	"major" : OMQ::version_major,
	"minor" : OMQ::version_minor,
	"sub"   : OMQ::version_sub,
	"patch" : OMQ::version_patch,
	"rel"	: OMQ::version_release,
    "full"  : OMQ::version,
	"code"  : OMQ::version_code,
};

string key = shift ARGV;
printf("%s", MAP{key});

