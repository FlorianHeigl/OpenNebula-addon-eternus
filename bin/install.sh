#!/bin/bash

# exit on any error
set -o pipefail
set -e

# resolve installer path and copy the driver bits from below there
cp $( dirname $0 )/../datastore/eternus/* /var/lib/one/remotes/datastore/eternus/
cp $( dirname $0 )/../tm/eternus/* /var/lib/one/remotes/tm/eternus/
chmod 755 /var/lib/one/remotes/*/eternus/*

# sync the updated driver to a list of all active compute nodes
# the list is gathered using the ONE cli
onehost list | grep on| awk '{system("onehost sync "$1" --force")}'
