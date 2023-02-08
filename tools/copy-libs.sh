#!/bin/sh

MODULES="module-oracle module-pgsql module-mysql module-asn1 module-xmlsec module-tibae module-tibrv module-sybase module-yaml module-ncurses module-ssh2 module-uuid module-gnu-java module-xml module-json module-openldap"

CMAKE_MODULES="module-magic module-sysconf module-fsevent module-linenoise"

if [ -z "$1" ]; then
    TARG="$OMQ_DIR"
else
    TARG="$1"
fi

if [ -z "$QORE_SRC_DIR" ]; then
    QORE_SRC_DIR=~/src/qore/qore
fi

SYS=`uname -s`
echo system is $SYS

if [ "$SYS" = "HP-UX" ]; then
    SL=sl
elif [ "$SYS" = "Darwin" ]; then
    SL=dylib
    MODSL=so
else
    SL=so
fi

if [ -z "$MODSL" ]; then
    MODSL=$SL
fi

cd $QORE_SRC_DIR/lib/.libs
if [ "$SYS" = "Darwin" ]; then
    LIBFILE=`ls -rt libqore.*.dylib | tail -1`
elif [ "$SYS" = "HP-UX" ]; then
    LIBFILE=`ls -rt libqore.$SL.*.* | tail -1`
else
    LIBFILE=`ls -rt libqore.$SL.*.*.* | tail -1`
fi
if [ -z "$LIBFILE" ]; then
    echo missing dynamic library
    exit
fi
cd ../..

#mkdir -p $TARG/lib/modules/auto

#rm -rf $TARG/lib/modules/*.qmod $TARG/lib/*.${SL}*
rm -rf $TARG/lib/*.${SL}*

# do system-dependent actions
if [ "$SYS" = "HP-UX" ]; then
    SL=sl
    cp -apv /opt/gnu/lib/libpcre.sl* $TARG/lib
    cp -apv /opt/gnu/lib/libssl.sl* $TARG/lib
    cp -apv /opt/gnu/lib/libcrypto.sl* $TARG/lib
    cp -apv /opt/gnu/lib/libz.sl* $TARG/lib
    cp -apv /opt/gnu/lib/libxml2.sl* $TARG/lib
    cp -apv /opt/gnu/lib/libpq.sl* $TARG/lib
    cp -apv /opt/gnu/lib/libyaml*.sl* $TARG/lib
elif [ "$SYS" = "SunOS" ]; then
    cp -apv /opt/gnu/lib/libpcre.so* $TARG/lib
    if [ -n "`file /opt/gnu/lib/libqore.so|grep 64`" ]; then
	cp -apv /opt/gnu/lib/64/libssl.so* $TARG/lib
	cp -apv /opt/gnu/lib/64/libcrypto.so* $TARG/lib
    else
	cp -apv /opt/gnu/lib/libssl.so* $TARG/lib
	cp -apv /opt/gnu/lib/libcrypto.so* $TARG/lib
    fi
    cp -apv /opt/gnu/lib/libxml2.so* $TARG/lib
    cp -apv /opt/gnu/lib/liblzma.so* $TARG/lib
    cp -apv /opt/gnu/lib/libxslt.so* $TARG/lib
    cp -apv /opt/gnu/lib/libpq.so* $TARG/lib
    cp -apv /opt/gnu/lib/libz.so* $TARG/lib
    cp -apv /opt/gnu/lib/libssh2.so* $TARG/lib
    cp -apv /opt/gnu/lib/libxmlsec1*.so* $TARG/lib
    cp -apv /opt/gnu/lib/libltdl.so* $TARG/lib
    cp -apv /opt/gnu/lib/libyaml*.so* $TARG/lib
    cp -apv /opt/csw/lib/libgmp.so.1[0-9]* $TARG/lib
    cp -apv /opt/csw/lib/libmpfr.so.[4-9]* $TARG/lib
    cp -apv /opt/gnu/lib/libgcc_s.so.[0-9]* $TARG/lib
    cp -apv /opt/gnu/lib/libldap_r-2.4.so.[0-9]* $TARG/lib
    cp -apv /opt/gnu/lib/liblber-2.4.so.[0-9]* $TARG/lib
    cp -apv /opt/gnu/lib/libmagic.so.[0-9]* $TARG/lib
    cp -apv /opt/csw/lib/libiconv.so.[0-9]* $TARG/lib
elif [ "$SYS" = "Linux-disabled" ]; then
    if [ -n "`uname -m|grep x86_64`" ]; then
	lib=lib64
    else
	lib=lib
    fi

    if [ -n "`ls /$lib/libpcre.so.*|tail -1` 2>/dev/null" ]; then
	cp -apv /$lib/libpcre* $TARG/lib
    else
	cp -apv /usr/$lib/libpcre.so* $TARG/lib
    fi
    if [ -n "`ls /$lib/libssl.so.*|tail -1` 2>/dev/null" ]; then
	cp -apv /$lib/libssl* /$lib/libcrypto* $TARG/lib
    else
	cp -apv /usr/$lib/libssl.so* $TARG/lib
	cp -apv /usr/$lib/libcrypto.so* $TARG/lib
    fi
    cp -apv /usr/$lib/libxml2.so* $TARG/lib
    cp -apv /usr/$lib/libpq.so* $TARG/lib
    cp -apv /usr/$lib/libz.so* $TARG/lib
    cp -apv /usr/$lib/libyaml*.so* $TARG/lib
elif [ "$SYS" = "Linux" ]; then
    if [ -n "`uname -m|grep x86_64`" ]; then
	lib=lib64
    else
	lib=lib
    fi

    cp -apv /usr/$lib/libyaml*.so* $TARG/lib
    cp -apv /usr/$lib/libssh2*.so* $TARG/lib
    cp -apv /opt/gnu/lib64/libmpfr.so.* $TARG/lib
    cp -apv /opt/gnu/lib64/libgmp.so.* $TARG/lib
#elif [ "$SYS" = "Darwin" ]; then
    #gcp -apv /sw/lib/libpcre.*dylib $TARG/lib
fi

lib=lib/.libs/$LIBFILE

if [ ! -f $lib ]; then
    echo missing $lib
    exit
fi

cd $QORE_SRC_DIR/
files=`find lib/.libs -name libqore\* ! -type d|grep -v dSYM|grep -v \.la`
cp -apRv $files $TARG/lib

#module_dir=`echo $QORE_SRC_DIR|sed -e 's/\/[^\/]*$//' -e 's/qore\/branches//'`
#
#cd $module_dir
#for a in $MODULES; do
#    echo checking $a
#    if [ "$SYS" = "SunOS" ]; then
#	find $a/ -name \*.${MODSL} -exec cp -v {} $TARG/lib/modules \;
#    else
#	find $a/ -name \*.${MODSL} \! -path \*dSYM\* -exec cp -v {} $TARG/lib/modules \;
#    fi
#done
#for a in $CMAKE_MODULES; do
#    echo checking $a
#    find $a/ -name \*.qmod|while read m; do
#        f=`basename $m|sed 's/-api.*.qmod//'`
#	cp -v $m $TARG/lib/modules/$f.qmod
#    done
#done
cd $TARG/lib
if [ "$SYS" = "Linux" -a "$2" != "rpm" ]; then
    make-dbg.sh $LIBFILE
elif [ "$SYS" = "HP-UX" ]; then
    chatr +s enable $LIBFILE >/dev/null
    echo chatr +s enable $LIBFILE
fi

# rename modules
cd modules
#ls *${MODSL} | while read a; do fn=`echo $a|cut -f1 -d.`; echo mv $a $fn.qmod; mv $a $fn.qmod; done

# make debugging files on Linux
if [ "$SYS" = "Linux" -a "$2" != "rpm" ]; then
    make-dbg.sh *qmod
fi
