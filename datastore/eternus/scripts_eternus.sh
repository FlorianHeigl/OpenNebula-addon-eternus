#!/usr/bin/env bash
# -------------------------------------------------------------------------- #
# Copyright 2014-2016, Laurent Grawet <dev@grawet.be>                        #
# 2020, Eternus version, Florian Heigl <fhe@deepthink.ag>                    #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #


# SSH connect timeout for Eternus operations
CONNECT_TIMEOUT=15

# flock timeout for eternus_lock function
FLOCK_TIMEOUT=600

# flock lockfile for eternus_lock function
FLOCK_LOCKFILE="/var/lock/one/.eternus.lock"

# flock file descriptor for eternus_lock function
FLOCK_FD=204

# Use ddpt instead of dd to speed up data transferts using sparse copy
USE_DDPT=1

#BLOCKDEV=blockdev
DDPT=ddpt
#DMSETUP=dmsetup
#FIND=find
FLOCK=flock
#HEAD=head
MULTIPATH=multipath
#OD=od
#TEE=tee

function eternus_lock {
    local STATUS
    STATUS=0
    eval "exec $FLOCK_FD> $FLOCK_LOCKFILE"
    $FLOCK -w $FLOCK_TIMEOUT -x $FLOCK_FD
    STATUS=$?
    if [ $STATUS -ne 0 ]; then
        log_error "Error, lock wait timeout (${FLOCK_TIMEOUT}s) exceeded for $FLOCK_LOCKFILE"
        error_message "Error, lock wait timeout (${FLOCK_TIMEOUT}s) exceeded for $FLOCK_LOCKFILE"
        exit $STATUS 
    fi
}

function eternus_unlock {
    $FLOCK -u $FLOCK_FD
}


function eternus_ssh_exec_and_log
{
    eternus_lock
    local SSH_EXEC_OUT SSH_EXEC_RC
    SSH_EXEC_OUT=`$SSH -o ConnectTimeout=$CONNECT_TIMEOUT "$1" "$2" 2>&1`
    SSH_EXEC_RC=$?
    eternus_unlock

    if [ $SSH_EXEC_RC -ne 0 ]; then
        log_error "Command \"$2\" failed: $SSH_EXEC_OUT"

        if [ -n "$3" ]; then
            error_message "$3"
        else
            error_message "Error executing $2: $SSH_EXEC_OUT"
        fi

        exit $SSH_EXEC_RC
    fi
}

function eternus_ssh_monitor_and_log
{
    eternus_lock
    local SSH_EXEC_OUT SSH_EXEC_RC
    SSH_EXEC_OUT=`$SSH -o ConnectTimeout=$CONNECT_TIMEOUT "$1" "$2" 2>&1`
    SSH_EXEC_RC=$?
    eternus_unlock

    if [ $SSH_EXEC_RC -ne 0 ]; then
        log_error "Command \"$2\" failed: $SSH_EXEC_OUT"

        if [ -n "$3" ]; then
            error_message "$3"
        else
            error_message "Error executing $2: $SSH_EXEC_OUT"
        fi

        exit $SSH_EXEC_RC
    fi
    echo "$SSH_EXEC_OUT"
}

# TEST: OK
function eternus_get_vvol_uid {
    local VVOL_NAME ARRAY_MGMT_IP STATUS VVOL_UID
    VVOL_NAME="$1"
    ARRAY_MGMT_IP="$2"
    STATUS=0
# ex:     3 one-3                            Available                 TPV               OFF        -                     -    0 RAIDGRP-1              - -                    20480              - Disable    Default   Thin       600000E00ABC0000002C13F800030000 Default  Follow Host Response          

    VVOL_UID=$( eternus_ssh_monitor_and_log "${ARRAY_MGMT_IP}" \
         "show volumes -mode detail" | grep "${ARRAY_POOL_NAME}" | grep -w "${VVOL_NAME}" | awk '{print tolower($17)}' )
    if [ -n "$VVOL_UID" ]; then
        echo "$VVOL_UID"
        exit $STATUS
    else
        STATUS=1
        log_error "Error vvol UID for $VVOL_NAME"
        error_message "Error getting vvol UID for $VVOL_NAME"
        exit $STATUS
    fi
}

# TEST: OK
function eternus_get_vvol_name {
    local VVOL_UID ARRAY_MGMT_IP STATUS VVOL_NAME
    VVOL_UID="$1"
    ARRAY_MGMT_IP="$2"
    STATUS=0
    VVOL_NAME=$( eternus_ssh_monitor_and_log "${ARRAY_MGMT_IP}" \
         "show volumes -mode detail" | grep "${ARRAY_POOL_NAME}" | grep -i "${VVOL_UID}" | awk '{print $2}' )
    if [ -n "$VVOL_NAME" ]; then
        echo "$VVOL_NAME"
        exit $STATUS
    else
        STATUS=1
        log_error "Error getting vvol name for $VVOL_UID"
        error_message "Error getting vvol name for $VVOL_UID"
        exit $STATUS 
    fi
}

# TEST: OK
function eternus_get_vvol_size {
    local VVOL_NAME ARRAY_MGMT_IP STATUS VVOL_SIZE
    VVOL_NAME="$1"
    ARRAY_MGMT_IP="$2"
    STATUS=0
    VVOL_SIZE=$( eternus_ssh_monitor_and_log "${ARRAY_MGMT_IP}" \
        "show volumes -mode detail" | grep "${ARRAY_POOL_NAME}" | grep -w "${VVOL_NAME}" | awk '{print ($12)}' )
    if [ -n "$VVOL_SIZE" ]; then
        echo "$VVOL_SIZE"
        exit $STATUS
    else
        STATUS=1
        log_error "Error getting vvol size for $VVOL_NAME"
        error_message "Error getting vvol size for $VVOL_NAME"
        exit $STATUS
    fi
}

# REMOVE (used in ds/rm, tm/elete, tm/mvds)
#function eternus_lsvvoldependentmaps {
#    local VVOL_NAME ARRAY_MGMT_IP i
#    local -a FCMAP
#    VVOL_NAME="$1"
#    ARRAY_MGMT_IP="$2"
#
#    while IFS= read -r line; do
#        FCMAP[i++]="$line"
#    done < <(eternus_ssh_monitor_and_log $ARRAY_MGMT_IP "lsfcmap -nohdr -delim : -filtervalue source_vvol_name=$VVOL_NAME")
#    echo "${FCMAP[@]}"
#}

# TEST: OK
function eternus_map {
    local ARRAY_MGMT_IP HOST VVOL MAP_CMD
    ARRAY_MGMT_IP="$1"
    HOST="$2"
    VVOL="$3"
    # get list of mapped luns in our lun group
    FREE_LUN_CMD="$( eternus_ssh_monitor_and_log "${ARRAY_MGMT_IP}" \
        "show lun-group -lg-name OPENNEBULA" | awk '$1 ~ /^[0-9]/ { print $1}' )"

    # find first unused LUN ID
    FREE_LUN=$( for i in {0..255} ; do if [[ ! "${FREE_LUN_CMD[*]}" =~ $i ]] ; then echo "${i}" ; break ; fi ; done )

    # TODO: grep Error here or in eternus_ssh_monitor_and_log. let's see.
    if [[ -n ${FREE_LUN} ]]; then
        MAP_CMD=$( eternus_ssh_monitor_and_log "${ARRAY_MGMT_IP}" \
            "set lun-group -lg-name OPENNEBULA -volume-name ${VVOL} -lun ${FREE_LUN}" )
    else
        "Error mapping vvol $VVOL to $HOST"
    fi
}

# TEST: OK
function eternus_unmap {
    local ARRAY_MGMT_IP HOST VVOL UNMAP_CMD
    ARRAY_MGMT_IP="$1"
    HOST="$2"
    VVOL="$3"
    LUN_ID=$( eternus_ssh_monitor_and_log "${ARRAY_MGMT_IP}" \
        "show lun-group -lg-name OPENNEBULA" | grep -w "${VVOL}" | awk '{print $1}' )
    UNMAP_CMD=$( eternus_ssh_monitor_and_log "${ARRAY_MGMT_IP}" \
        "delete lun-group -lg-name OPENNEBULA -lun $LUN_ID" )
    exit $?
}

# UNUSED.
#function iscsiadm_discovery_login {
#    local PORTAL
#    PORTAL=("$@")
#    for i in ${PORTAL[@]}; do
#      echo "$ISCSIADM -m discovery -t st -p $i --login"
#    done
#}

# UNUSED
#function iscsiadm_node_logout {
#    local PORTAL
#    PORTAL=("$@")
#    for i in ${PORTAL[@]}; do
#      echo "$ISCSIADM -m node -p $i --logoutall all"
#    done
#}

# UNUSED
function iscsiadm_session_rescan {
    echo "$ISCSIADM -m session --rescan"
    sleep 2
}

# TEST (ds/mkfs,ds/clone,ds/cp,tm/delete,tm/mvds,tm/postmigrate,tm/mv)
function multipath_flush {
    local MAP_NAME
    MAP_NAME="$1"
    echo "$MULTIPATH -f $MAP_NAME"
}

# TEST
function multipath_rescan {
    echo "$MULTIPATH"
    sleep 4
}

# TEST
function get_datastore_attr {
    local DS_ID DS_ATTR ATTR
    DS_ID="$1"
    DS_ATTR="$2"
    ATTR=$( onedatastore show "$DS_ID" | $GREP -w "$DS_ATTR" | $CUT -d\" -f2 )
    if [ -n "${ATTR}" ]; then
        echo "$ATTR"
    fi
}

# TEST
function clone_command {
    local IF OF
    IF="$1"
    OF="$2"
    if [ $USE_DDPT -eq 1 ]; then
        echo "$DDPT if=$IF of=$OF bs=512 bpt=128 oflag=sparse"
    else
        echo "$DD if=$IF of=$OF bs=64k conv=nocreat"
    fi
}
