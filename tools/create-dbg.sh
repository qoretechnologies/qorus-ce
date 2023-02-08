#!/bin/sh

if [ -z "$1" ]; then
    echo missing release label
    exit
fi

sys=`uname -s`
arch=`uname -p`
if [ $arch = "i686" -o $arch = "athlon" ]; then
    arch=i386
fi

# do not overwrite debug files
TARG=$QORUS_RELEASE_DIR/qorus-$1-debug-$sys-$arch.tar.gz

if [ -f "$TARG" ]; then
    tt=$TARG
    n=0
    while [ -f $TARG ]; do
	n=$(($n + 1))
	TARG=$tt-$n
    done
fi

tar cvzf $TARG `find . -name \*.dbg`
if [ $? -gt 0 ]; then
    exit
fi
find . -name \*.dbg -exec rm -v {} \;
