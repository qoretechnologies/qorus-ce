#!/usr/bin/env qore

%new-style
%strict-args
%require-types
%enable-all-warnings

FileLineIterator i(ARGV[0]);

bool delfunc;
bool dup;

while (i.next()) {
    string line = i.getValue();
    if (line =~ /\|/) {
        list<auto> l = line.split("|");
        if (!delfunc && l[3] =~ /Qore Function/) {
            delfunc = True;
        }
        if (delfunc) {
            splice l, 3, 1;
        }
        if (l[1] =~ /^!%Qore .*/) {
            string nstr = l[1];
            nstr =~ s/^!%Qore (.*)/!%Python $1/;
            splice l, 1, 0, nstr;
            dup = True;
        } else if (l[1] =~ /^@ref OMQ::/) {
            string nstr = l[1];
            nstr =~ s/(UserApi::.*) "WorkflowApi::/$1 "wfapi./;
            nstr =~ s/(UserApi::.*) "ServiceApi::/$1 "svcapi./;
            nstr =~ s/(UserApi::.*) "JobApi::/$1 "jobapi./;
            nstr =~ s/(UserApi::.* "\w+)::/$1./;
            splice l, 1, 0, nstr;
        } else if (dup) {
            string nstr = l[1];
            splice l, 1, 0, nstr;
        }
        line = l.join("|");
    } else if (delfunc) {
        remove delfunc;
        remove dup;
    }
    printf("%s\n", line);
}

