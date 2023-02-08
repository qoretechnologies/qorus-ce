#!/bin/sh

VMAJOR=`grep const.*version_major lib/qorus-version.ql|grep -v '^[ \t]*\#'|head -1|cut -f2 -d= |cut -b2- |cut -f1 -d\;`
VMINOR=`grep const.*version_minor lib/qorus-version.ql|grep -v '^[ \t]*\#'|head -1|cut -f2 -d= |cut -b2- |cut -f1 -d\;`
VSUB=`grep const.*version_sub lib/qorus-version.ql|grep -v '^[ \t]*\#'|head -1|cut -f2 -d= |cut -b2- |cut -f1 -d\;`
PATCH=`grep const.*version_patch lib/qorus-version.ql|grep -v '^[ \t]*\#'|head -1|cut -f2 -d= |cut -b2- |cut -f1 -d\; | sed 's/"//g' | grep -v NOTHING`
RMOD=`grep const.*version_release lib/qorus-version.ql|grep -v '^[ \t]*\#'|head -1|cut -f2 -d=|cut -b2-|cut -f1 -d\;|sed 's/"//g'|grep -v NOTHING`

ver=$VMAJOR.$VMINOR.$VSUB

if [ -n "$PATCH" ]; then
    ver=$ver.$PATCH
fi

if [ -n "$RMOD" ]; then
    ver=${ver}_${RMOD}
fi

echo $ver
