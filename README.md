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

## Limitations

Sharing of volumes (i.e. for a HA cluster) does not match well with the 
OpenNebula use case.
Such storage should be directly attached (i.e. also using iSCSI) to the virtual machines and not managed by OpenNebula.

## Installation

TBA


## Usage


## Examples
