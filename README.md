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

The Eternus requires a *working*, *reliable* multipath setup.

Look out for timeouts
```
[6012868.647650]  connection1:0: detected conn error (1020)

``` 
These indicated a missing mpath/alua issue, array wants to serve this LUN over a port that you have a working session with.

another message indicating an incorrect setup:
```
[7316736.333286] sd 11:0:0:0: Warning! Received an indication that the LUN assignments on this target have changed. The Linux SCSI layer does not automatical
```


## Limitations

Sharing of volumes (i.e. for a HA cluster) does not match well with the 
OpenNebula use case.
Such storage should be directly attached (i.e. also using iSCSI) to the virtual machines and not managed by OpenNebula.

The Eternus has severely limited snapshot support geared mostly towards off-site replication and proprietary features as used i.e. by VEEAM(r). As such, live snapshots of running VMs *cannot be created*.
This takes away some use cases you might wish for. Some others can be solved using clones, which *can be created*.

The secondary controller of the Eternus is not able to run management tasks.
Currently only the primary controller can be used.


## Installation


### extend your sudoers configuration

OpenNebula already created `/etc/sudoers.d/opennebula`.

You'll need to add a few command aliasses:

```
Cmnd_Alias ONE_EXTSTOR = /sbin/multipath, /bin/dd, /usr/bin/ddpt, /sbin/blockdev, /usr/bin/tee, /sbin/dmsetup, /usr/bin/rescan-scsi-bus.sh

oneadmin ALL=(ALL) NOPASSWD: ONE_MISC, ONE_NET, ONE_LVM, ONE_ISCSI, ONE_OVS, ONE_XEN, ONE_CEPH, ONE_MARKET, ONE_HA, ONE_EXTSTOR
```

Using `tee` is based on existing ONE community code. It has  a certain security risk 


### Install the driver

*Deploy* the files to `/var/lib/one/remotes/(datastore|tm)`.
A `install.sh` is provided (you might need to update the source path in it)

Make *modifications* to `/etc/one/oned.conf`:

* DATASTORE_MAD

```
DATASTORE_MAD = [
    EXECUTABLE = "one_datastore",
    ARGUMENTS  = "-t 15 -d dummy,fs,lvm,ceph,dev,iscsi_libvirt,vcenter,eternus -s shared,ssh,ceph,fs_lvm,q
cow2,vcenter"
]
```

* DS_MAD_CONF

```
DS_MAD_CONF = [
    NAME = "eternus", REQUIRED_ATTRS = "DISK_TYPE,BRIDGE_LIST,ARRAY_NAME,ARRAY_MGMT_IP,ARRAY_POOL_NAME",
    PERSISTENT_ONLY = "NO"
]
```

* TM_MAD

```
TM_MAD = [
    EXECUTABLE = "one_tm",
    ARGUMENTS = "-t 15 -d dummy,lvm,shared,fs_lvm,qcow2,ssh,ceph,dev,vcenter,iscsi_libvirt,eternus"
]
```

* TM_MAD_CONF

```
TM_MAD_CONF = [
    NAME = "eternus", LN_TARGET = "NONE", CLONE_TARGET = "SELF", SHARED = "YES", 
    ALLOW_ORPHANS = "YES", TM_MAD_SYSTEM = "ssh", LN_TARGET_SSH = "SYSTEM",
    CLONE_TARGET_SSH = "SYSTEM",  DISK_TYPE_SSH = "FILE", DS_MIGRATE = "NO",  
    DRIVER = "raw", CLONE_TARGET_SHARED = "SELF", DISK_TYPE_SHARED = "block"
]
```

Restart the OpenNebula core to load the new drivers.

```$ sudo systemctl restart opennebula```

Check the log files.

PSA: It's worth knowing that if you have some mistake / unsupported setting in `oned.conf` that might show only later when you try to change one of the attributes. For that reason, it's best to try adding some attribute as a test.
That means, when you create the datastore, go to Storage/Datastores and create an attribute called "TEST" while looking at oned.log.


### Create the *datastore definition*

Here's a working example:

```
oneadmin@one-frontend:~$ onedatastore show 120
DATASTORE 120 INFORMATION                                                       
ID             : 120
NAME           : ETERNUS-1
USER           : your-gui-user
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

To create that yourself, you need to make a text file (i.e. my-eternus-2.txt).
It should contain `NAME=MYDATASTORE` followed by everything after `DATASTORE TEMPLATE`

Then create the datastore from that file:

```
$ onedatastore create my-eternus-2.txt
```
It'll print the ID of the new datastore and start monitoring it.
Until the ssh access works flawless, it'll probably show the datastore at 1MB size, or other weird things might happen.
This is due to how the OpenNebula monitoring works. It seems that states like `ERROR` will not appear for datastores at all.


### ssh access to Eternus

We recommend to create a `.ssh/config` for the oneadmin user on all BRIDGE_LIST hosts.

```
oneadmin@one-frontend:~$ cat ~/.ssh/config 
Host 192.168.12.34
  IdentityFile /var/lib/one/.ssh/id_rsa-eternus
  Ciphers aes128-cbc
  RequestTTY force
  User my-storage-user
```

We recommend using a dedicated key like in the above example.

The Public key has to be converted to "ietf" format and uploaded to the eternus.
If it is accepted by the Eternus it'll show in the list of deployed keys.
If it doesn't like it, it'll be like you didn't upload a key at all.

* If you want, you can also use `ssh-keyscan 192.168.12.34` to scan the ssh-keys or store them in DNS as `SSHFP` records. 
* The second controller will show a different ssh key


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
