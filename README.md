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

## Installation

TBA


## Usage


## Examples
