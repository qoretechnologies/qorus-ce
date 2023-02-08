#!/bin/sh

if [ "$1" = "" ]; then
    echo "Error: Java source file not given" >&2
    exit 1
fi
if [ "$2" = "" ]; then
    echo "Error: Javadoc destination file not given" >&2
    exit 1
fi

cat $1 | \
sed 's/@throws Throwable /@throws /g' | \
sed 's/@throws /@throws Throwable /g' | \
sed 's/@par \(.*\)$/<b>\1<\/b>/g' | \
sed 's/@see @ref\(.*\)$/@see \1/g' | \
sed 's/@ref //g' | \
sed 's/@showinitializer//g' | \
sed 's/<li>\\c /<li>/g' | \
sed 's/\\c "/"/g' | \
sed 's/\\c \([a-zA-Z0-9_.-]*\)/"\1"/g' | \
#sed 's/\\c \([a-zA-Z0-9_.-]*\)/<tt>\1<\/tt>/g' | \
sed 's/\\a \([a-zA-Z0-9_.-]*\)/<i>\1<\/i>/g' | \
sed 's/@code{\.java}/<blockquote><pre>{@code/g; s/@code{\.py}/<blockquote><pre>{@code/g; s/@endcode/}<\/pre><\/blockquote>/g' | \
sed 's/@QorusMethod/{@literal @}QorusMethod/g' > $2
