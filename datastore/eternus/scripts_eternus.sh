#!/usr/bin/env bash

# OpenNebula driver for Fujitsu Eternus DX series
# https://github.com/deepthinkag/OpenNebula-addon-eternus/
# <fhe@deepthink.ag>

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

DDPT=ddpt
FLOCK=flock
MULTIPATH=multipath

# must be extended to include all possible driver data
function get_xpath_info() {
XPATH="${DRV_PATH}/../../datastore/xpath.rb -b $DRV_ACTION"

unset i XPATH_ELEMENTS

while IFS= read -r -d '' element; do
    XPATH_ELEMENTS[i++]="$element"
done < <($XPATH     /DS_DRIVER_ACTION_DATA/DATASTORE/BASE_PATH \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/RESTRICTED_DIRS \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SAFE_DIRS \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/UMASK \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/BRIDGE_LIST \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/DEBUG \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/ARRAY_MGMT_IP \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/ARRAY_POOL_NAME \
                    /DS_DRIVER_ACTION_DATA/IMAGE/FSTYPE \
                    /DS_DRIVER_ACTION_DATA/IMAGE/SIZE \
                    /DS_DRIVER_ACTION_DATA/IMAGE/NAME \
                    /DS_DRIVER_ACTION_DATA/IMAGE/SOURCE \
                    /DS_DRIVER_ACTION_DATA/IMAGE/PATH \
                    /DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/MD5 \
                    /DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/SHA1 \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/STAGING_DIR )


                    
BASE_PATH="${XPATH_ELEMENTS[0]}"
RESTRICTED_DIRS="${XPATH_ELEMENTS[1]}"
SAFE_DIRS="${XPATH_ELEMENTS[2]}"
UMASK="${XPATH_ELEMENTS[3]}"
BRIDGE_LIST="${XPATH_ELEMENTS[4]:-$BRIDGE_LIST}"
DEBUG="${XPATH_ELEMENTS[5]:-NO}"
ARRAY_MGMT_IP="${XPATH_ELEMENTS[6]}"
ARRAY_POOL_NAME="${XPATH_ELEMENTS[7]}"
FSTYPE="${XPATH_ELEMENTS[8]}"
SIZE="${XPATH_ELEMENTS[9]:-0}"
NAME="${XPATH_ELEMENTS[10]}"
SOURCE="${XPATH_ELEMENTS[11]}"
IMAGE_PATH="${XPATH_ELEMENTS[12]}"
MD5="${XPATH_ELEMENTS[13]}"
SHA1="${XPATH_ELEMENTS[14]}"
STAGING_DIR="${XPATH_ELEMENTS[15]:-/var/tmp}"

export BASE_PATH RESTRICTED_DIRS SAFE_DIRS UMASK BRIDGE_LIST FSTYPE SIZE NAME SOURCE IMAGE_PATH MD5 SHA1 STAGING_DIR
export DEBUG
export ARRAY_MGMT_IP ARRAY_POOL_NAME

}

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
         "show volumes -mode detail" | grep "${ARRAY_POOL_NAME}" | grep -E "(${VVOL_NAME}\s)" | awk '{print tolower($17)}' )
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
        "show volumes -mode detail" | grep "${ARRAY_POOL_NAME}" | grep -E "(${VVOL_NAME}\s)" | awk '{print ($12)}' )
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


# TEST: OK
# BUG: what if already mapped?
function eternus_map {
    local ARRAY_MGMT_IP HOST VVOL MAP_CMD
    ARRAY_MGMT_IP="$1"
    HOST="$2"
    VVOL="$3"
    # get list of mapped luns in our lun group
    FREE_LUN_CMD="$( eternus_ssh_monitor_and_log "${ARRAY_MGMT_IP}" \
        "show lun-group -lg-name OPENNEBULA" | awk '$1 ~ /^[0-9]/ { print $1" "$3}' )"
    
    # take this list and then check if lun is already mapped! if yes, just return!
    if TEST_LUN_MAPPED=$( echo "$FREE_LUN_CMD" | grep -E "(${VVOL}$)" ); then
        LUN_ID=$( echo "$TEST_LUN_MAPPED" | awk '{print $1}' )
        echo "$LUN_ID"
        return 0
    fi

    # find first unused LUN ID
    FREE_LUN=$( for i in {0..255} ; do if [[ ! "${FREE_LUN_CMD[*]}" =~ $i ]] ; then echo "${i}" ; break ; fi ; done )

    # TODO: grep Error here or in eternus_ssh_monitor_and_log. let's see.
    if [[ -n ${FREE_LUN} ]]; then
        MAP_CMD=$( eternus_ssh_monitor_and_log "${ARRAY_MGMT_IP}" \
            "set lun-group -lg-name OPENNEBULA -volume-name ${VVOL} -lun ${FREE_LUN}" )
    else
        "Error mapping vvol $VVOL to $HOST"
    fi
    echo "$FREE_LUN"
    return 0
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
    echo "iscsiadm -m session --rescan"
    sleep 2
}

# TEST (ds/mkfs,ds/clone,ds/cp,tm/delete,tm/mvds,tm/postmigrate,tm/mv)
function multipath_flush {
    local MAP_NAME
    MAP_NAME="$1"
    echo "sudo multipath -f $MAP_NAME"
}

# TEST
function multipath_rescan {
    echo "sudo multipath"
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

function rescan_scsi_bus {
  local LUN
  local FORCE
  LUN="$1"
  [ "$2" == "force" ] && FORCE=" --forcerescan"
  echo "HOSTS=\$(cat /proc/scsi/scsi | awk -v RS=\"Type:\" '\$0 ~ \"Model: ETERNUS_DXL\" {print \$0}' |grep -Po \"scsi[0-9]+\"|grep -Eo \"[0-9]+\" |sort|uniq|paste -sd \",\" -)"
  #rescan-scsi-bus hat einen bug, manuell updaten
  echo "$SUDO /usr/bin/rescan-scsi-bus.sh --hosts=\$HOSTS -m -s -a -r -u -f --sparselun  --nooptscan $FORCE"
  #echo "for _scan in /sys/class/scsi_host/host_*/scan ; do echo \"- - -\" | sudo tee \$_scan ; done"
}

function get_vv_name {
  local NAME_WWN
  NAME_WWN="$1"
  echo "$NAME_WWN" | awk -F: '{print $1}'
}

function get_vv_wwn {
  local NAME_WWN
  NAME_WWN="$1"
  echo "$NAME_WWN" | awk -F: '{print $2}'
}

function discover_lun {
    local LUN
    local WWN
    LUN="$1"
    WWN="$2"
    cat <<EOF
        sudo iscsiadm -m session --rescan
        sleep 2
        $(rescan_scsi_bus "$LUN")
        sleep 2
        $(multipath_rescan)

        DEV="/dev/mapper/3$WWN"

        # Wait a bit for new mapping
        COUNTER=1
        while [ ! -e \$DEV ] && [ \$COUNTER -le 10 ]; do
            sleep 1
            COUNTER=\$((\$COUNTER + 1))
        done
        if [ ! -e \$DEV ]; then
            # Last chance to get our mapping
            $(multipath_rescan)
            COUNTER=1
            while [ ! -e "\$DEV" ] && [ \$COUNTER -le 10 ]; do
                sleep 1
                COUNTER=\$((\$COUNTER + 1))
            done
        fi
        # Exit with error if mapping does not exist
        if [ ! -e \$DEV ]; then
            echo "multipath device does not exist"
            exit 1
        fi

        DM_HOLDER=\$($SUDO dmsetup ls -o blkdevname | grep -Po "(?<=3$WWN\s\()[^)]+")
        DM_SLAVE=\$(ls /sys/block/\${DM_HOLDER}/slaves)
        # Wait a bit for mapping's paths
        COUNTER=1
        while [ ! "\${DM_SLAVE}" ] && [ \$COUNTER -le 10 ]; do
            sleep 1
            COUNTER=\$((\$COUNTER + 1))
        done
        # Exit with error if mapping has no path
        if [ ! "\${DM_SLAVE}" ]; then
            echo "multipath slave does not exist"
            exit 1
        fi
EOF
}

function remove_lun {
    local WWN
    WWN="$1"
    cat <<EOF
      DEV="/dev/mapper/3$WWN"
      # if the mpath device is gone, just exit
      if ! [ -b $DEV ]; then
          #$SUDO /usr/bin/rescan-scsi-bus.sh -r -m
          exit 0
      fi
      DM_HOLDER=\$($SUDO dmsetup ls -o blkdevname | grep -Po "(?<=3$WWN\s\()[^)]+")
      DM_SLAVE=\$(ls /sys/block/\${DM_HOLDER}/slaves)

      $(multipath_flush "\$DEV")

      unset device
      for device in \${DM_SLAVE}
      do
          if [ -e /dev/\${device} ]; then
              $SUDO blockdev --flushbufs /dev/\${device}
              echo 1 | $SUDO tee /sys/block/\${device}/device/delete
          fi
      done
EOF
}

