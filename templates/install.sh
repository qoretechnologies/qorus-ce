#!/bin/sh
#
# Qorus installer script
# Copyright (C) 2003 - 2020 Qore Technologies s.r.o.

# put any script actions here that should be executed **BEFORE** the install
pre_install() {
    # do not remove the following line if this function is otherwise empty or this script will fail on some shells
    test
}

# put any script actions here that should be executed **AFTER** the install
# (for example, delete services, reset workflows, etc)
post_install() {
    # do not remove the following line if this function is otherwise empty or this script will fail on some shells
    test
}

###########################################
### do not change anything below this line!
###########################################

args="$@"

error() {
    echo ERROR: $*
    echo correct the errors listed above and try again
    exit 1
}

warning() {
    printf "*** WARNING: $*\n"
}

do_db_error() {
    printf "you cannot complete the installation until the file:\n"
    printf "    $OPT_FILE\n"
    printf "exists and is configured with the omq datasource.\n"
    if [ -f "$OPT_FILE.example" ]; then
        printf "Please see the file:\n"
        printf "    $OPT_FILE.example\n"
        printf "or the Qorus documentation for more information.\n"
    else
        printf "Please see the Qorus documentation for more information.\n"
    fi
    printf "\n"
    printf "*** When the file is properly configured, run this install.sh\n"
    printf "***     script again to complete the installation\n"
    exit;
}

check_environment() {
    if [ "$SHUTDOWN_BEFORE" = "Y" ]; then
        checkStopped BEFORE
    fi

    TODAY=`date +%Y-%m-%d`

    # check environment
    if [ -z "$OMQ_DIR" ]; then
        if [ -x /usr/bin/qorus ]; then
            OMQ_DIR=LSB
        elif [ -x /opt/qorus/bin/qorus ]; then
            OMQ_DIR=/opt/qorus
        else
            error \$OMQ_DIR has not been set in the environment
        fi
    fi

    # check for target directory
    if [ ! -d "$OMQ_DIR" ]; then
        error target directory \"$OMQ_DIR\" does not exist
    fi

    if [ "$OMQ_DIR" = "LSB" ]; then
        OMQ_DIR=/var/opt/qorus
        OPT_FILE=/etc/qorus/options
        DB_FILE=/etc/qorus/dbparams
        QORUS_BIN=/usr/bin
        REPO_DIR=$OMQ_DIR/user/repos
        LSB=1
    else
        OPT_FILE="$OMQ_DIR/etc/options"
        DB_FILE="$OMQ_DIR/etc/dbparams"
        QORUS_BIN="$OMQ_DIR/bin"
        REPO_DIR="$OMQ_DIR/etc"
        LSB=0
    fi

    # check if $QORUS_BIN is in the path (unless on Windows)
    if [ -z "`echo $PATH|grep \"$QORUS_BIN\"`" -a "$SYSTEM" != "Windows" ]; then
        warning adding $QORUS_BIN to the PATH
        PATH="$QORUS_BIN:$PATH"
        export PATH
        fixed_path=yes
        env_changed=yes
    fi

    # check if $OMQ_DIR is writable by install.sh
    if [ ! -w "$OMQ_DIR" ]; then
        error target directory $OMQ_DIR is not writable
    fi

    # check if $OMQ_DIR/lib is in the library path (only if there are libraries in $OMQ_DIR/lib)
    if [ $LSB -eq 0 -a "$SYSTEM" != "Windows" ] && [ -n "`find $OMQ_DIR/lib -maxdepth 1 -name '*'.$soname -print -quit`" ]; then
        if [ "$SYSTEM" = "OSX" ]; then
            if [ -z "`echo $DYLD_LIBRARY_PATH | grep \"$OMQ_DIR/lib\"`" ]; then
                warning adding $OMQ_DIR/lib to DYLD_LIBRARY_PATH
                DYLD_LIBRARY_PATH="$OMQ_DIR/lib:$DYLD_LIBRARY_PATH"
                export DYLD_LIBRARY_PATH
                fixed_dyld_path=yes
                env_changed=yes
            fi
        elif [ "$SYSTEM" = "HP-UX" ]; then
            if [ -z "`echo $SHLIB_PATH | grep \"$ORACLE_HOME/lib\"`" ]; then
                warning adding $OMQ_DIR/lib to SHLIB_PATH
                SHLIB_PATH="$OMQ_DIR/lib:$SHLIB_PATH"
                export SHLIB_PATH
                fixed_shlib_path=yes
                env_changed=yes
            fi
        else  # check if $OMQ_DIR/lib is in the LD_LIBRARY_PATH
            if [ -z "`echo $LD_LIBRARY_PATH | grep \"$OMQ_DIR/lib\"`" ]; then
                warning adding $OMQ_DIR/lib to LD_LIBRARY_PATH
                LD_LIBRARY_PATH="$OMQ_DIR/lib:$LD_LIBRARY_PATH"
                export LD_LIBRARY_PATH
                fixed_ld_path=yes
                env_changed=yes
            fi
        fi

    fi

    # check for valid QORE_INCLUDE_DIR if not on Windows
    if [ "$SYSTEM" != "Windows" ]; then
        if [ -z "$QORE_INCLUDE_DIR" ]; then
            warning adding $OMQ_DIR/qlib to QORE_INCLUDE_DIR
            QORE_INCLUDE_DIR="$OMQ_DIR/qlib"
            export QORE_INCLUDE_DIR
            fixed_qi_path=yes
            env_changed=yes
        elif [ -z "`echo $QORE_INCLUDE_DIR | grep \"$OMQ_DIR/qlib\"`" ]; then
            warning adding $OMQ_DIR/qlib to QORE_INCLUDE_DIR
            QORE_INCLUDE_DIR="$OMQ_DIR/qlib:$QORE_INCLUDE_DIR"
            export QORE_INCLUDE_DIR
            fixed_qi_path=yes
            env_changed=yes
        fi
    fi
}

parse_omq_ds() {
    # check $OPT_FILE file for omq datasource first
    if [ -f "$OPT_FILE" ]; then
        omqds="`grep \"^qorus\.systemdb:\" \"$OPT_FILE\" 2>/dev/null`"
    fi

    if [ -z "$omqds" ]; then
        # check $DB_FILE file for omq datasource second for backwards compatibility
        if [ -f "$DB_FILE" ]; then
            omqds="`grep omq= \"$DB_FILE\" 2>/dev/null`"
        fi
    fi

    echo $omqds
}

install_release() {
    # make sure everything is there
    for a in $USERCODE; do
        if [ ! -f "$a" ]; then
            error missing $a
        fi
    done
    for a in $LOAD_SCRIPTS; do
        if [ ! -f "$a" ]; then
            error missing load script: releases/$a
        fi
    done

    # change to target directory
    cd "$OMQ_DIR"

    # install user code
    if [ -n "$USERCODE" ]; then
        echo installing Qorus user code from: $USERCODE
        gunzip -dc "$dir/$USERCODE" |tar xf -
    fi

    # make release directory if it doesn't already exist
    if [ ! -d "$OMQ_DIR"/releases ]; then
        mkdir "$OMQ_DIR/releases"
    fi

    # install release load scripts
    if [ -n "$LOAD_SCRIPTS" ]; then
        printf "installing release files: "
        for a in $LOAD_SCRIPTS; do
            $CP "$dir/$a" "$OMQ_DIR/releases"
        done
        echo done
    fi

    if [ -n "$LOAD_SCRIPTS" ]; then
        # check for omq datasource
        omqds=$(parse_omq_ds)
        if [ -z "$omqds" ]; then
            printf "ERROR: the system schema (omq) is not defined in $OPT_FILE\n"
            do_db_error
        fi

        schema=`"$QORUS_BIN/schema-tool"`
        rc=$?
        # if there was an error
        if [ $rc -ne 0 ]; then
            if [ $rc -eq 1 ]; then
                error schema status is MISSING
            elif [ $rc -eq 2 ]; then
                error schema status is INVALID
            elif [ $rc -eq 3 ]; then
                error schema status is VERSION-ERROR
            elif [ $rc -eq 5 ]; then
                error cannot initialize client library
            else
                error "schema status is UNKNOWN (code $rc)"
            fi
        fi
        if [ -z "$schema" ]; then
            error unable to determine schema status
        fi
        echo schema status is $schema

        printf "executing schema release loader files\n"
        for a in $LOAD_SCRIPTS; do
            # pass all unhandled args as args for oload ($@) to handle e.g. tablespace names
            echo executing: oload $args @$a
            oload $args @$a #| tee $OLOAD_OUTPUT
            if [ $? -ne 0 ]; then
                error "error in load script $a, aborting installation"
            fi
        done
        echo done executing release files
    fi
}

post_install_messages() {
    if [ "$RESTART_AFTER" = "Y" -o "$env_changed" = "yes" ]; then
        printf "\n"
        printf "**********************************************************\n"
        printf "ATTENTION: MANUAL STEPS NECESSARY TO COMPLETE INSTALLATION\n"
        printf "**********************************************************\n"
        printf "\n"
    fi

    if [ "$env_changed" = "yes" ]; then

        printf "*** this script made changes to your environment in order to install\n"
        printf "*** Qorus Integration Engine.  You must make these changes permanent\n"
        printf "*** in order to start the application.  List of changes:\n\n"

        if [ "$fixed_path" = "yes" ]; then
            printf "   PATH=%s\n\n" "$PATH"
        fi

        if [ "$fixed_ld_path" = "yes" ]; then
            printf "   LD_LIBRARY_PATH=%s\n\n" "$LD_LIBRARY_PATH"
        fi

        if [ "$fixed_dyld_path" = "yes" ]; then
            printf "   DYLD_LIBRARY_PATH=%s\n\n" "$DYLD_LIBRARY_PATH"
        fi

        if [ "$fixed_shlib_path" = "yes" ]; then
            printf "   SHLIB_PATH=%s\n\n" "$SHLIB_PATH"
        fi

        if [ "$fixed_qi_path" = "yes" ]; then
            printf "   QORE_INCLUDE_DIR=%s\n\n" "$OMQ_DIR/qlib"
        fi
    fi

    if [ "$RESTART_AFTER" = "Y" ]; then
        checkStopped AFTER
    fi

    if [ -z "$QORE" -a "$SHUTDOWN_BEFORE" = "Y" ]; then
        printf "\n"
        printf " *** Qorus may now be restarted\n"
        printf "\n"
    fi
}

check_release_contents() {
    cd `dirname $0`
    dir=`pwd`

    USERCODE=`ls *.tar.gz 2>/dev/null`
    LOAD_SCRIPTS=`ls releases/*.qrf 2>/dev/null`
    REPOSITORY=`ls *.dat 2>/dev/null`

    if [ "$verbose" = yes -a -n "$USERCODE" ]; then
        echo USERCODE: $USERCODE
    fi

    if [ "$verbose" = yes -a -n "$LOAD_SCRIPTS" ]; then
        echo LOAD_SCRIPTS: $LOAD_SCRIPTS
    fi

    if [ "$verbose" = yes -a -n "$REPOSITORY" ]; then
        echo REPOSITORY: $REPOSITORY
    fi

    if [ -z "$USERCODE" -a -z "$LOAD_SCRIPTS" -a -z "$REPOSITORY" ]; then
        error no release contents
    fi
}

set_system_vars() {
    # set install variables
    CP=cp
    SYSTEM=`uname -s`

    if [ $SYSTEM = "OSX" ]; then
        dlp="$DYLD_LIBRARY_PATH"
        soname=dylib
        dname=DYLD_LIBRARY_PATH
    elif [ $SYSTEM = "HP-UX" ]; then
        if [ -n "`uname -m| grep 9000`" ]; then
            ARCH="parisc"
        else
            ARCH="itanium"
        fi
        OSVER_MAJOR=`uname -r|cut -f2 -d.`

        dlp="$SHLIB_PATH"
        dname=SHLIB_PATH
        soname=sl
    elif [ -n "`echo $SYSTEM|grep ^MINGW32`" ]; then
        SYSTEM=Windows
        # assume forward and backwards compatibility with Windows for now
        OSVER_MAJOR=1
        OSVER_MINOR=0
        cpu=`wmic cpu get caption|tail -2|head -1|cut -f1 -d\ `
        if [ "$cpu" = "Intel64" ]; then
            ARCH=x86_64
        elif [ "$cpu" = "x86" ]; then
            ARCH=i386
        else
            ARCH=$cpu
        fi
    else
        dlp="$LD_LIBRARY_PATH"
        dname=LD_LIBRARY_PATH
        soname=so

        if [ $SYSTEM = "SunOS" ]; then
            SYSTEM=Solaris
            OSVER_MAJOR=`uname -r|cut -f2 -d.`
        elif [ $SYSTEM = "Linux" ]; then
            # get kernel version info
            OSVER_MAJOR=`uname -r|cut -f1 -d.`
            OSVER_MINOR=`uname -r|cut -f2 -d.`
        elif [ $SYSTEM = "Darwin" ]; then
            SYSTEM=OSX
            # get kernel version info
            OSVER_MAJOR=`sw_vers -productVersion|cut -f1 -d.`
            OSVER_MINOR=`sw_vers -productVersion|cut -f2 -d.`
        fi
        ARCH=`uname -p`
        if [ "$ARCH" = "unknown" ]; then
            ARCH=`uname -m`
        fi
        if [ $ARCH = "i586" -o $ARCH = "i686" -o $ARCH = "athlon" ]; then
            ARCH=i386
        elif [ $ARCH = "i386" -a $SYSTEM = "Solaris" ]; then
            if [ "`isainfo|grep 64`" ]; then
                ARCH=x86_64
            fi
        fi
        # make sure it's not really an x86_64 box by checking uname -m
        if [ $ARCH = "i386" ]; then
            ta=`uname -m`
            if [ $ta = "x86_64" ]; then
                ARCH=x86_64
            fi
        fi
    fi
}

set_system_vars
check_release_contents
check_environment

echo checks are OK, installing from $dir

pre_install

install_release

# check if qorus is currently running
# we cannot rely on the return status of ocmd because it was broken in the 1.8.0 releases up to 1.8.0.p2
output=`ocmd ping 2>/dev/null`
if [ "$output" = "OK" ]; then
    running=yes
else
    # if Qorus is not running, then ignore any RESTART_AFTER flag
    unset RESTART_AFTER
fi

post_install

echo installation complete!

post_install_messages
