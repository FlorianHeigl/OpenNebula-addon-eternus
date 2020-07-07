#!/bin/bash

set -e

cp ~deepthink/OpenNebula-addon-eternus/datastore/eternus/* /var/lib/one/remotes/datastore/eternus/
cp ~deepthink/OpenNebula-addon-eternus/tm/eternus/* /var/lib/one/remotes/tm/eternus/
chmod 755 /var/lib/one/remotes/*/eternus/*
onehost sync 0 --force
onehost sync 1 --force
