# Fujtisu Eternus CLI commands

Overview of tested commands for the Eternus.
Upstream documentation overview is at 
https://www.fujitsu.com/global/support/products/computing/storage/manuals/manuals-config.html

the CLI guide linked from there is:
http://docs.ts.fujitsu.com/dl.aspx?id=d50e9f72-a69d-4602-9140-321f91e0f31d


## Running commands

* create a user with correct privileges in the storage
* generate a ssh key for the management user `ssh-keygen -t rsa -b 4096 -f id_rsa-eternus-demo`. (Likely you need a key with no passphrase for OpenNebula <= 5.12)
* convert the key to 'ietf' format `ssh-keygen -e -f id_rsa-eternus-demo.pub > id_rsa-coda-eternus.pub.ietf`
* Install the key on the eternus
* run the commands using `ssh -t user@storage "command"` for pseudo tty allocation


## Volume and initiator Management

### thin pool usage

```CLI> show thin-pro-pools
Thin Pro             Disk         RAID     Status             Total       Provisioned         Used        Used      Warn-  Atten-  Encryp- Chunk
No. Name             Attribute    Level                       Capacity    Capacity    Rate(%) Capacity    Status    ing(%) tion(%) tion    Size(MB)
--- ---------------- ------------ -------- ------------------ ----------- ----------- ------- ----------- --------- ------ ------- ------- --------
  0 RAIDGRP-1            Online       RAID1+0  Available          38.44 TB    58.01 TB        151 606.58 GB   Normal        90       - Disable       21
```


### volume: create

```
CLI> create volume -pool-name RAIDGRP-1 -type tpv -size 10gb -name one-1         
```

* runtime ca. 2s
* does not return an ID

### volume: list

```
CLI> show volumes
Volume                                 Status                    Type              RG or TPP or FTRP     Size(MB)  Copy
No.   Name                                                                         No.  Name                       Protection
----- -------------------------------- ------------------------- ----------------- ---- ---------------- --------- ----------
    0 ForeignVol1                         Available                 TPV                  0 RAIDGRP-1             39845888 Disable    
    1 ForeignVol2                         Available                 TPV                  0 RAIDGRP-1             20971520 Disable    
    2 dt-test-001                      Available                 TPV                  0 RAIDGRP-1                10240 Disable    
    3 one-1                            Available                 TPV                  0 RAIDGRP-1                10240 Disable  
```

#### csv

```
CLI> show volumes -csv
show volumes -csv
[Volume No.],[Volume Name],[Status],[Type],[RG or TPP or FTRP No.],[RG or TPP or FTRP Name],[Size(MB)],[Copy Protection]
0,ForeignVol1,Available,TPV,0,RAIDGRP-1,39845888,Disable
1,ForeignVol2,Available,TPV,0,RAIDGRP-1,20971520,Disable
2,dt-test-001,Available,TPV,0,RAIDGRP-1,10240,Disable
3,one-3,Available,TPV,0,RAIDGRP-1,20480,Disable
4,test,Available,TPV,0,RAIDGRP-1,102400,Disable

```

* runtime less than 1s
* correct luns can be filtered using `grep -w -E "one-[0-9]*"`
* snapshots / clones might have a suffix
* size is always in MB


### volume: delete 

```
CLI> delete volume -volume-name one-1
```

* runtime: 3-4s
* volume IDs are autoincremented. 
* if an intermediate volume id gets freed (deleted), it will be recycled
* searches can only be done by name

### initiator groups: list

* found two existing groups of 1 host eah
* this isn't good for a multi-node cluster since it misaligns the scsi ids
* should match per array

```
CLI> show lun-groups 
LUN Group             LUN Overlap
No.  Name             Volumes
---- ---------------- -----------
   0 LUN1             No         
   1 V2               No         
   2 lg-dt-test       No   
```

#### initiator groups: lun mapping detail view

for this, a detail view needs to be done individually

```
CLI> show lun-groups -lg-name lg-dt-test
LUN Group No.             [2]
LUN Group Name            [lg-dt-test]
Veeam Storage Integration [-]
LUN  Volume                                 Status                    Size(MB)  LUN Overlap UID
     No.   Name                                                                 Volume
---- ----- -------------------------------- ------------------------- --------- ----------- --------------------------------
   0     2 dt-test-001                      Available                     10240 No          600000F12DEF0000002C13F800020000
```

We seem to find our SCSI serial and LUN ID right here.

### lun mapping: create

```
CLI> set lun-group -lg-name lg-dt-test -volume-name one-3 -lun 1
```

there's no way to automatically pick the lun ID, it has to be done like this.

#### example output after mapping a few LUNs

```
CLI> show volumes                       
Volume                                 Status                    Type              RG or TPP or FTRP     Size(MB)  Copy
No.   Name                                                                         No.  Name                       Protection
----- -------------------------------- ------------------------- ----------------- ---- ---------------- --------- ----------
    0 ForeignVol1                         Available                 TPV                  0 RAIDGRP-1             39845888 Disable    
    1 ForeignVol2                         Available                 TPV                  0 RAIDGRP-1             20971520 Disable    
    2 dt-test-001                      Available                 TPV                  0 RAIDGRP-1                10240 Disable    
    3 one-3                            Available                 TPV                  0 RAIDGRP-1                10240 Disable    
    4 one-2                            Available                 TPV                  0 RAIDGRP-1                10240 Disable    

CLI> show lun-groups -lg-name lg-dt-test                        
LUN Group No.             [2]
LUN Group Name            [lg-dt-test]
Veeam Storage Integration [-]
LUN  Volume                                 Status                    Size(MB)  LUN Overlap UID
     No.   Name                                                                 Volume
---- ----- -------------------------------- ------------------------- --------- ----------- --------------------------------
   0     2 dt-test-001                      Available                     10240 No          600000F12DEF0000002C13F800020000
   1     3 one-3                            Available                     10240 No          600000F12DEF0000002C13F800030000
   2     4 one-2                            Available                     10240 No          600000F12DEF0000002C13F800040000

```

* the "0N0000" of the serial matches nicely the internal "number" of the volume.
* but we are also shown the name


### lun mapping: delete


```
CLI> delete lun-group -lg-name lg-dt-test -lun 2
CLI> show lun-groups -lg-name lg-dt-test        
LUN Group No.             [2]
LUN Group Name            [lg-dt-test]
Veeam Storage Integration [-]
LUN  Volume                                 Status                    Size(MB)  LUN Overlap UID
     No.   Name                                                                 Volume
---- ----- -------------------------------- ------------------------- --------- ----------- --------------------------------
   0     2 dt-test-001                      Available                     10240 No          600000F12DEF0000002C13F800020000
   1     3 one-3                            Available                     10240 No          600000F12DEF0000002C13F800030000
```

* without parameter the whole group is deleted!
* it is not possible to work with the ForeignVol name
* should be ok since we drive this via the host and know the volume name...

```
CLI> delete volume -volume-name one-2
```


### lun: resize

```
CLI> expand volume -volume-name one-3 -size 20gb
```

* mind the OS side followup steps for this
