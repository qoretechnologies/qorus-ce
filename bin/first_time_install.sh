#!/bin/sh

# if we do not have the environment set up, try to source /opt/qorus/bin/env.sh if it exists
if [ -z "$OMQ_DIR" -a -f /opt/qorus/bin/env.sh ]; then
    . /opt/qorus/bin/env.sh
fi

# as of Qorus 6.0 this is performed by calling schema-tool -m
schema-tool -m
