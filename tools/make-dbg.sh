#!/bin/sh

for a in $*; do
    if [ -f $a ]; then
	printf "$a -> $a.dbg\n"
	objcopy --only-keep-debug $a $a.dbg
	objcopy --strip-debug $a
	objcopy --add-gnu-debuglink=$a.dbg $a
    else
	echo skipping $a
    fi
done
