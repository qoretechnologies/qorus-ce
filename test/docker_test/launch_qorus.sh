#!/bin/bash

set -e
set -x

. /tmp/env.sh

# turn on core dumps
ulimit -c unlimited

# start Qorus
qorus --log-level=ALL --debug-system
