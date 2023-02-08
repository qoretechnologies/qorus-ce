#!/usr/bin/env qore


%exec-class DoxygenMakeTarballs

%new-style
%require-our

const opts = (
    "gzip"      : "g,gzip",
    "zip"       : "z,zip",
    "help"      : "h,help"
    );

class DoxygenMakeTarballs {
    private {
        hash o; # options
        *string docdir;
    }

    constructor() {
        printf("\nmaking documentation packages...\n");
        my GetOpt g(opts);
        o = g.parse3(\ARGV);
        if (o.help)
            DoxygenMakeTarballs::usage();

        docdir = shift ARGV;
        if (!exists docdir) {
            printf("Unspecified docdir. See --help\n");
            exit(1);
        }

        if (!ARGV) {
            printf("Unspecified prefix. See --help\n");
            exit(1);
        }

        my Dir d();
        if (!d.chdir(docdir)) {
            printf("Docdir '%s' does not exist. See --help\n", docdir);
            exit(1);
        }
        chdir(docdir);

        list l = ();
        printf("L> %N\n", ARGV);
        map l += d.listDirs("^" + $1 + "\$"), ARGV;

        printf("Processing: %y\n", l);

        string tar = makeTar(l);

	my string cmdBzip2 = sprintf("bzip2 -fk %s", tar);
	makeCall(cmdBzip2);

        makeQtHelp(l[0]);

        if (o.gzip) {
	    string cmdGzip = sprintf("gzip -fk %s", tar);
	    makeCall(cmdGzip);
        }
        makeCall("rm %s", tar);

        if (o.zip) {
            string cmdZip = sprintf("zip -FSrq %s.zip %s", l[0], (foldl $1 + " " + $2, l));
            makeCall(cmdZip);
        }
    }

    private makeQtHelp(string dirFile) {
        printf("QtHelp> generating for %s: ", dirFile);
        chdir(dirFile);
        if (system(sprintf("qhelpgenerator index.qhp -o ../%s.qch", dirFile)))
            printf("failed\n");
        else
            printf("OK\n");
        chdir("..");
    }

    private string makeTar(list l) {
        string files = foldl $1 + " " + $2, l;
        string tar = sprintf("%s.tar", l[0]);
        if (PlatformOS == "Darwin")
            makeCall("tar -cf %s -L %s", tar, files);
        else
            makeCall("tar -cf %s -h %s", tar, files);
        return tar;
    }

    private makeCall(string cmd) {
        cmd = vsprintf(cmd, argv);
        printf("exec: %s: ", cmd); flush();
        if (system(cmd)) {
            printf("failed: %s\n", strerror());
            exit(1);
        }
        printf("OK\n");
    }

    static usage() {
         printf("usage: %s [options] docdir prefix
Script takes directories in existing docdir and it makes a tarball for it.
Prefix is the documentation directory prefix. For example \"qorus-\" will
take all documentation directories as they lay in 'docdir'/qorus-*
Files in tar.bz2 format are created by default.
Options:
  -g,--gzip             use additional tar.gz
  -z,--zip              use additional zip compression (zip required)
  -h,--help             this help text
", get_script_name());
          exit(1);
    }

}
