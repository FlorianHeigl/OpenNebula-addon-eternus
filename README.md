# OpenNebula Fujitsu Eternus Storage Driver


## Description

Eternus is a series of disk storage arrays.
They can be connected using i.e. iSCSI or Fibrechannel.

The driver will handle volume management for the volumes used by OpenNebula 
on these storage devices.

The volumes are block-based, one per virtual machine, and it will be possible to use one storage array from multiple hosts.




## Development


## Author

Florian Heigl with support by Kris Feldsam 


## Compatibility

This addon is intended for OpenNebula 5.x+


## Requirements

TBA

The Eternus requires a working, reliable multipath setup.
Look out timeouts (no mpath)
```
[6012868.647650]  connection1:0: detected conn error (1020)

```

or incorrect setup
```
[7316736.333286] sd 11:0:0:0: Warning! Received an indication that the LUN assignments on this target have changed. The Linux SCSI layer does not automatical
```


## Limitations

Sharing of volumes (i.e. for a HA cluster) does not match well with the 
OpenNebula use case.
Such storage should be directly attached (i.e. also using iSCSI) to the virtual machines and not managed by OpenNebula.

The Eternus has severely limited snapshot support geared mostly towards off-site replication and proprietary features as used i.e. by VEEAM(r). As such, snapshots of running VMs cannot be created.

## Installation


### Install the driver

*Deploy* the files to `/var/lib/one/remotes/(datastore|tm)`.
A install.sh is provided (you might need to update the source path in it)

Make *modifications* to `/etc/one/oned.conf`:

* DATASTORE_MAD

```DATASTORE_MAD = [
    EXECUTABLE = "one_datastore",
    ARGUMENTS  = "-t 15 -d dummy,fs,lvm,ceph,dev,iscsi_libvirt,vcenter,eternus -s shared,ssh,ceph,fs_lvm,q
cow2,vcenter"
]```

* DS_MAD_CONF

```DS_MAD_CONF = [
    NAME = "eternus", REQUIRED_ATTRS = "DISK_TYPE,BRIDGE_LIST,ARRAY_NAME,ARRAY_MGMT_IP,ARRAY_POOL_NAME",
    PERSISTENT_ONLY = "NO"
]```

* TM_MAD

```TM_MAD = [
    EXECUTABLE = "one_tm",
    ARGUMENTS = "-t 15 -d dummy,lvm,shared,fs_lvm,qcow2,ssh,ceph,dev,vcenter,iscsi_libvirt,eternus"
]```

* TM_MAD_CONF

```TM_MAD_CONF = [
    NAME = "eternus", LN_TARGET = "NONE", CLONE_TARGET = "SELF", SHARED = "YES", 
    ALLOW_ORPHANS = "YES", TM_MAD_SYSTEM = "ssh", LN_TARGET_SSH = "SYSTEM",
    CLONE_TARGET_SSH = "SYSTEM",  DISK_TYPE_SSH = "FILE", DS_MIGRATE = "NO",  
    DRIVER = "raw", CLONE_TARGET_SHARED = "SELF", DISK_TYPE_SHARED = "block"
]```

Restart the OpenNebula core to load the new drivers.

```$ sudo systemctl restart opennebula```

Check the log files.

PSA: It's worth knowing that if you have some mistake / unsupported setting in `oned.conf` that might show only later when you try to change one of the attributes. For that reason, it's best to try adding some attribute as a test.


### Create the *datastore definition*

Here's a working example:

```
oneadmin@one-frontend:~$ onedatastore show 120
DATASTORE 120 INFORMATION                                                       
ID             : 120
NAME           : ETERNUS-1
USER           : deepthink
GROUP          : oneadmin
CLUSTERS       : 0
TYPE           : IMAGE
DS_MAD         : eternus
TM_MAD         : eternus
BASE PATH      : /var/lib/one//datastores/120
DISK_TYPE      : BLOCK
STATE          : READY

DATASTORE CAPACITY                                                              
TOTAL:         : 58.2T
FREE:          : 57.6T
USED:          : 38.4T
LIMIT:         : -

PERMISSIONS                                                                     
OWNER          : um-
GROUP          : u--
OTHER          : ---

DATASTORE TEMPLATE                                                              
ALLOW_ORPHANS="YES"
ARRAY_MGMT_IP="192.168.12.34"
ARRAY_NAME="ETERNUS-1"
ARRAY_POOL_NAME="RAIDGROUP-1"
BRIDGE_LIST="one-frontend-ip"
CLONE_TARGET="SELF"
CLONE_TARGET_SSH="SYSTEM"
DEBUG="YES"
DISK_TYPE="BLOCK"
DISK_TYPE_SSH="FILE"
DRIVER="raw"
DS_MAD="eternus"
LN_TARGET="NONE"
LN_TARGET_SSH="SYSTEM"
RESTRICTED_DIRS="/"
SAFE_DIRS="/var/tmp"
TM_MAD="eternus"
TM_MAD_SYSTEM="ssh"
TYPE="IMAGE_DS"
```


### ssh access to Eternus

We recommend to create a `.ssh/config` for the oneadmin user on all BRIDGE_LIST hosts.

```
oneadmin@one-frontend:~$ cat ~/.ssh/config 
Host 192.168.12.34
  IdentityFile /var/lib/one/.ssh/id_rsa-eternus
  Ciphers aes128-cbc
  RequestTTY force
  User deepthink
```

We recommend using a dedicated key like in the above example.

The Public key has to be converted to "ietf" format and uploaded to the eternus.
If it is accepted by the Eternus it'll show in the list of deployed keys.
If it doesn't like it, it'll be like you didn't upload a key at all.


## Usage

You create the datastore as above. It should automatically become useable - 
you'll know once you see the usage data show up.
The datastore driver supported use as an IMAGE datastore.
The iSCSI sessions and multipathing *configuration* are not managed by the driver.
The *multipath* devices are managed by the driver.

For individual VMs, if you have multiple system datastores, you should stick with a simple ssh-based one.


### Debugging

All driver components support generating debug output.
The log files
Logging is enabled by setting the attribute `DEBUG=yes` on the datastore.
The directory `/var/tmp/one` needs to exist and be writeable to the oneadmin user on the frontend. The drivers log to `/var/tmp/one/<action>.log` and show their calling parameters as `/var/tmp/one/<action>.params`.
The logs are overwritten on each call.



## Examples
