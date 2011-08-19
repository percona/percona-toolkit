#!/bin/bash

TESTS=6

# ############################################################################
cat <<EOF > $TMPDIR/expected
         BBU | 100% Charged, Temperature 18C, isSOHGood=Yes
EOF

cat <<EOF > $TMPDIR/in
BBU status for Adapter: 0

BatteryType: BBU
Voltage: 4072 mV
Current: 0 mA
Temperature: 18 C
Firmware Status: 00000000

Battery state: 

GasGuageStatus:
  Fully Discharged        : No
  Fully Charged           : Yes
  Discharging             : Yes
  Initialized             : Yes
  Remaining Time Alarm    : No
  Remaining Capacity Alarm: No
  Discharge Terminated    : No
  Over Temperature        : No
  Charging Terminated     : No
  Over Charged            : No

Relative State of Charge: 100 %
Charger Status: Complete
Remaining Capacity: 867 mAh
Full Charge Capacity: 867 mAh
isSOHGood: Yes

Exit Code: 0x00
EOF
parse_lsi_megaraid_bbu_status $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

# ############################################################################
cat <<EOF > $TMPDIR/expected

  PhysiclDev Type State   Errors Vendor  Model        Size
  ========== ==== ======= ====== ======= ============ ===========
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
EOF

cat <<EOF > $TMPDIR/in
                                     
Adapter #0

Enclosure Device ID: 32
Slot Number: 0
Device Id: 0
Sequence Number: 2
Media Error Count: 0
Other Error Count: 0
Predictive Failure Count: 0
Last Predictive Failure Event Seq Number: 0
PD Type: SAS
Raw Size: 70007MB [0x88bb93a Sectors]
Non Coerced Size: 69495MB [0x87bb93a Sectors]
Coerced Size: 69376MB [0x8780000 Sectors]
Firmware state: Online
SAS Address(0): 0x5000c500079f8cf9
SAS Address(1): 0x0
Connected Port Number: 0(path0) 
Inquiry Data: SEAGATE ST373455SS      S5273LQ2DZ33            
Foreign State: None 
Media Type: Hard Disk Device

Enclosure Device ID: 32
Slot Number: 1
Device Id: 1
Sequence Number: 2
Media Error Count: 0
Other Error Count: 0
Predictive Failure Count: 0
Last Predictive Failure Event Seq Number: 0
PD Type: SAS
Raw Size: 70007MB [0x88bb93a Sectors]
Non Coerced Size: 69495MB [0x87bb93a Sectors]
Coerced Size: 69376MB [0x8780000 Sectors]
Firmware state: Online
SAS Address(0): 0x5000c500079f5c35
SAS Address(1): 0x0
Connected Port Number: 1(path0) 
Inquiry Data: SEAGATE ST373455SS      S5273LQ2D9RH            
Foreign State: None 
Media Type: Hard Disk Device

Enclosure Device ID: 32
Slot Number: 2
Device Id: 2
Sequence Number: 2
Media Error Count: 0
Other Error Count: 0
Predictive Failure Count: 0
Last Predictive Failure Event Seq Number: 0
PD Type: SAS
Raw Size: 70007MB [0x88bb93a Sectors]
Non Coerced Size: 69495MB [0x87bb93a Sectors]
Coerced Size: 69376MB [0x8780000 Sectors]
Firmware state: Online
SAS Address(0): 0x5000c500079fc0c9
SAS Address(1): 0x0
Connected Port Number: 2(path0) 
Inquiry Data: SEAGATE ST373455SS      S5273LQ2DPST            
Foreign State: None 
Media Type: Hard Disk Device

Enclosure Device ID: 32
Slot Number: 3
Device Id: 3
Sequence Number: 2
Media Error Count: 0
Other Error Count: 0
Predictive Failure Count: 0
Last Predictive Failure Event Seq Number: 0
PD Type: SAS
Raw Size: 70007MB [0x88bb93a Sectors]
Non Coerced Size: 69495MB [0x87bb93a Sectors]
Coerced Size: 69376MB [0x8780000 Sectors]
Firmware state: Online
SAS Address(0): 0x5000c500079dc339
SAS Address(1): 0x0
Connected Port Number: 3(path0) 
Inquiry Data: SEAGATE ST373455SS      S5273LQ2CKD5            
Foreign State: None 
Media Type: Hard Disk Device


Exit Code: 0x00
EOF
parse_lsi_megaraid_devices $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected


# ############################################################################
cat <<EOF > $TMPDIR/expected

  PhysiclDev Type State   Errors Vendor  Model        Size
  ========== ==== ======= ====== ======= ============ ===========
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
EOF

cat <<EOF > $TMPDIR/in
[root@pc-db1 ~]# /opt/MegaRAID/MegaCli/MegaCli64 -LdPdInfo -aALL
                                     
Adapter #0

Number of Virtual Disks: 2
Virtual Disk: 0 (Target Id: 0)
Name:
RAID Level: Primary-1, Secondary-0, RAID Level Qualifier-0
Size:69376MB
State: Optimal
Stripe Size: 64kB
Number Of Drives:2
Span Depth:1
Default Cache Policy: WriteBack, ReadAheadNone, Direct, No Write Cache if Bad BBU
Current Cache Policy: WriteBack, ReadAheadNone, Direct, No Write Cache if Bad BBU
Access Policy: Read/Write
Disk Cache Policy: Disk's Default
Number of Spans: 1
Span: 0 - Number of PDs: 2
PD: 0 Information
Enclosure Device ID: 32
Slot Number: 0
Device Id: 0
Sequence Number: 2
Media Error Count: 0
Other Error Count: 0
Predictive Failure Count: 0
Last Predictive Failure Event Seq Number: 0
PD Type: SAS
Raw Size: 70007MB [0x88bb93a Sectors]
Non Coerced Size: 69495MB [0x87bb93a Sectors]
Coerced Size: 69376MB [0x8780000 Sectors]
Firmware state: Online
SAS Address(0): 0x5000c500079f8cf9
SAS Address(1): 0x0
Connected Port Number: 0(path0) 
Inquiry Data: SEAGATE ST373455SS      S5273LQ2DZ33            
Foreign State: None 
Media Type: Hard Disk Device

PD: 1 Information
Enclosure Device ID: 32
Slot Number: 1
Device Id: 1
Sequence Number: 2
Media Error Count: 0
Other Error Count: 0
Predictive Failure Count: 0
Last Predictive Failure Event Seq Number: 0
PD Type: SAS
Raw Size: 70007MB [0x88bb93a Sectors]
Non Coerced Size: 69495MB [0x87bb93a Sectors]
Coerced Size: 69376MB [0x8780000 Sectors]
Firmware state: Online
SAS Address(0): 0x5000c500079f5c35
SAS Address(1): 0x0
Connected Port Number: 1(path0) 
Inquiry Data: SEAGATE ST373455SS      S5273LQ2D9RH            
Foreign State: None 
Media Type: Hard Disk Device

Virtual Disk: 1 (Target Id: 1)
Name:
RAID Level: Primary-1, Secondary-0, RAID Level Qualifier-0
Size:69376MB
State: Optimal
Stripe Size: 64kB
Number Of Drives:2
Span Depth:1
Default Cache Policy: WriteBack, ReadAheadNone, Direct, No Write Cache if Bad BBU
Current Cache Policy: WriteBack, ReadAheadNone, Direct, No Write Cache if Bad BBU
Access Policy: Read/Write
Disk Cache Policy: Disk's Default
Number of Spans: 1
Span: 0 - Number of PDs: 2
PD: 0 Information
Enclosure Device ID: 32
Slot Number: 2
Device Id: 2
Sequence Number: 2
Media Error Count: 0
Other Error Count: 0
Predictive Failure Count: 0
Last Predictive Failure Event Seq Number: 0
PD Type: SAS
Raw Size: 70007MB [0x88bb93a Sectors]
Non Coerced Size: 69495MB [0x87bb93a Sectors]
Coerced Size: 69376MB [0x8780000 Sectors]
Firmware state: Online
SAS Address(0): 0x5000c500079fc0c9
SAS Address(1): 0x0
Connected Port Number: 2(path0) 
Inquiry Data: SEAGATE ST373455SS      S5273LQ2DPST            
Foreign State: None 
Media Type: Hard Disk Device

PD: 1 Information
Enclosure Device ID: 32
Slot Number: 3
Device Id: 3
Sequence Number: 2
Media Error Count: 0
Other Error Count: 0
Predictive Failure Count: 0
Last Predictive Failure Event Seq Number: 0
PD Type: SAS
Raw Size: 70007MB [0x88bb93a Sectors]
Non Coerced Size: 69495MB [0x87bb93a Sectors]
Coerced Size: 69376MB [0x8780000 Sectors]
Firmware state: Online
SAS Address(0): 0x5000c500079dc339
SAS Address(1): 0x0
Connected Port Number: 3(path0) 
Inquiry Data: SEAGATE ST373455SS      S5273LQ2CKD5            
Foreign State: None 
Media Type: Hard Disk Device


Exit Code: 0x00
EOF
parse_lsi_megaraid_devices $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

# ############################################################################
cat <<EOF > $TMPDIR/expected

  VirtualDev Size      RAID Level Disks SpnDpth Stripe Status  Cache
  ========== ========= ========== ===== ======= ====== ======= =========
  0(no name) 69376MB   1 (1-0-0)      2     1-1   64kB Optimal WB, no RA
  1(no name) 69376MB   1 (1-0-0)      2     1-1   64kB Optimal WB, no RA
EOF

cat <<EOF > $TMPDIR/in
[root@pc-db1 ~]# /opt/MegaRAID/MegaCli/MegaCli64 -LdPdInfo -aALL
                                     
Adapter #0

Number of Virtual Disks: 2
Virtual Disk: 0 (Target Id: 0)
Name:
RAID Level: Primary-1, Secondary-0, RAID Level Qualifier-0
Size:69376MB
State: Optimal
Stripe Size: 64kB
Number Of Drives:2
Span Depth:1
Default Cache Policy: WriteBack, ReadAheadNone, Direct, No Write Cache if Bad BBU
Current Cache Policy: WriteBack, ReadAheadNone, Direct, No Write Cache if Bad BBU
Access Policy: Read/Write
Disk Cache Policy: Disk's Default
Number of Spans: 1
Span: 0 - Number of PDs: 2
PD: 0 Information
Enclosure Device ID: 32
Slot Number: 0
Device Id: 0
Sequence Number: 2
Media Error Count: 0
Other Error Count: 0
Predictive Failure Count: 0
Last Predictive Failure Event Seq Number: 0
PD Type: SAS
Raw Size: 70007MB [0x88bb93a Sectors]
Non Coerced Size: 69495MB [0x87bb93a Sectors]
Coerced Size: 69376MB [0x8780000 Sectors]
Firmware state: Online
SAS Address(0): 0x5000c500079f8cf9
SAS Address(1): 0x0
Connected Port Number: 0(path0) 
Inquiry Data: SEAGATE ST373455SS      S5273LQ2DZ33            
Foreign State: None 
Media Type: Hard Disk Device

PD: 1 Information
Enclosure Device ID: 32
Slot Number: 1
Device Id: 1
Sequence Number: 2
Media Error Count: 0
Other Error Count: 0
Predictive Failure Count: 0
Last Predictive Failure Event Seq Number: 0
PD Type: SAS
Raw Size: 70007MB [0x88bb93a Sectors]
Non Coerced Size: 69495MB [0x87bb93a Sectors]
Coerced Size: 69376MB [0x8780000 Sectors]
Firmware state: Online
SAS Address(0): 0x5000c500079f5c35
SAS Address(1): 0x0
Connected Port Number: 1(path0) 
Inquiry Data: SEAGATE ST373455SS      S5273LQ2D9RH            
Foreign State: None 
Media Type: Hard Disk Device

Virtual Disk: 1 (Target Id: 1)
Name:
RAID Level: Primary-1, Secondary-0, RAID Level Qualifier-0
Size:69376MB
State: Optimal
Stripe Size: 64kB
Number Of Drives:2
Span Depth:1
Default Cache Policy: WriteBack, ReadAheadNone, Direct, No Write Cache if Bad BBU
Current Cache Policy: WriteBack, ReadAheadNone, Direct, No Write Cache if Bad BBU
Access Policy: Read/Write
Disk Cache Policy: Disk's Default
Number of Spans: 1
Span: 0 - Number of PDs: 2
PD: 0 Information
Enclosure Device ID: 32
Slot Number: 2
Device Id: 2
Sequence Number: 2
Media Error Count: 0
Other Error Count: 0
Predictive Failure Count: 0
Last Predictive Failure Event Seq Number: 0
PD Type: SAS
Raw Size: 70007MB [0x88bb93a Sectors]
Non Coerced Size: 69495MB [0x87bb93a Sectors]
Coerced Size: 69376MB [0x8780000 Sectors]
Firmware state: Online
SAS Address(0): 0x5000c500079fc0c9
SAS Address(1): 0x0
Connected Port Number: 2(path0) 
Inquiry Data: SEAGATE ST373455SS      S5273LQ2DPST            
Foreign State: None 
Media Type: Hard Disk Device

PD: 1 Information
Enclosure Device ID: 32
Slot Number: 3
Device Id: 3
Sequence Number: 2
Media Error Count: 0
Other Error Count: 0
Predictive Failure Count: 0
Last Predictive Failure Event Seq Number: 0
PD Type: SAS
Raw Size: 70007MB [0x88bb93a Sectors]
Non Coerced Size: 69495MB [0x87bb93a Sectors]
Coerced Size: 69376MB [0x8780000 Sectors]
Firmware state: Online
SAS Address(0): 0x5000c500079dc339
SAS Address(1): 0x0
Connected Port Number: 3(path0) 
Inquiry Data: SEAGATE ST373455SS      S5273LQ2CKD5            
Foreign State: None 
Media Type: Hard Disk Device


Exit Code: 0x00
EOF
parse_lsi_megaraid_virtual_devices $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

# ############################################################################
cat <<EOF > $TMPDIR/expected

  VirtualDev Size      RAID Level Disks SpnDpth Stripe Status  Cache
  ========== ========= ========== ===== ======= ====== ======= =========
  0(no name) 69376MB   1 (1-0-0)      2      1-   64kB Optimal WB, no RA
  1(no name) 69376MB   1 (1-0-0)      2      1-   64kB Optimal WB, no RA
EOF

cat <<EOF > $TMPDIR/in
[root@pc-db1 ~]# /opt/MegaRAID/MegaCli/MegaCli64 -LDInfo -Lall -aAll
                                     

Adapter 0 -- Virtual Drive Information:
Virtual Disk: 0 (Target Id: 0)
Name:
RAID Level: Primary-1, Secondary-0, RAID Level Qualifier-0
Size:69376MB
State: Optimal
Stripe Size: 64kB
Number Of Drives:2
Span Depth:1
Default Cache Policy: WriteBack, ReadAheadNone, Direct, No Write Cache if Bad BBU
Current Cache Policy: WriteBack, ReadAheadNone, Direct, No Write Cache if Bad BBU
Access Policy: Read/Write
Disk Cache Policy: Disk's Default
Virtual Disk: 1 (Target Id: 1)
Name:
RAID Level: Primary-1, Secondary-0, RAID Level Qualifier-0
Size:69376MB
State: Optimal
Stripe Size: 64kB
Number Of Drives:2
Span Depth:1
Default Cache Policy: WriteBack, ReadAheadNone, Direct, No Write Cache if Bad BBU
Current Cache Policy: WriteBack, ReadAheadNone, Direct, No Write Cache if Bad BBU
Access Policy: Read/Write
Disk Cache Policy: Disk's Default

Exit Code: 0x00
EOF
parse_lsi_megaraid_virtual_devices $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected


# ############################################################################
cat <<EOF > $TMPDIR/expected
       Model | PERC 6/i Integrated, PCIE interface, 8 ports
       Cache | 256MB Memory, BBU Present
EOF

cat <<EOF > $TMPDIR/in
[root@pc-db1]# /opt/MegaRAID/MegaCli/MegaCli64  -AdpAllInfo -aALL
                                     
Adapter #0

==============================================================================
                    Versions
                ================
Product Name    : PERC 6/i Integrated
Serial No       : 1122334455667788
FW Package Build: 6.0.1-0080

                    Mfg. Data
                ================
Mfg. Date       : 06/08/07
Rework Date     : 06/08/07
Revision No     : 
Battery FRU     : N/A

                Image Versions In Flash:
                ================
FW Version         : 1.11.52-0349
BIOS Version       : NT13-2
WebBIOS Version    : 1.1-32-e_11-Rel
Ctrl-R Version     : 1.01-010B
Boot Block Version : 1.00.00.01-0008

                Pending Images In Flash
                ================
None

                PCI Info
                ================
Vendor Id       : 1000
Device Id       : 0060
SubVendorId     : 1028
SubDeviceId     : 1f0c

Host Interface  : PCIE

Number of Frontend Port: 0 
Device Interface  : PCIE

Number of Backend Port: 8 
Port  :  Address
0        5000c500079f8cf9 
1        5000c500079f5c35 
2        5000c500079fc0c9 
3        5000c500079dc339 
4        0000000000000000 
5        0000000000000000 
6        0000000000000000 
7        0000000000000000 

                HW Configuration
                ================
SAS Address     : 5001e4f021048f00
BBU             : Present
Alarm           : Absent
NVRAM           : Present
Serial Debugger : Present
Memory          : Present
Flash           : Present
Memory Size     : 256MB

                Settings
                ================
Current Time                     : 20:31:29 5/13, 2010
Predictive Fail Poll Interval    : 300sec
Interrupt Throttle Active Count  : 16
Interrupt Throttle Completion    : 50us
Rebuild Rate                     : 30%
PR Rate                          : 30%
Resynch Rate                     : 30%
Check Consistency Rate           : 30%
Reconstruction Rate              : 30%
Cache Flush Interval             : 4s
Max Drives to Spinup at One Time : 2
Delay Among Spinup Groups        : 12s
Physical Drive Coercion Mode     : 128MB
Cluster Mode                     : Disabled
Alarm                            : Disabled
Auto Rebuild                     : Enabled
Battery Warning                  : Enabled
Ecc Bucket Size                  : 15
Ecc Bucket Leak Rate             : 1440 Minutes
Restore HotSpare on Insertion    : Disabled
Expose Enclosure Devices         : Disabled
Maintain PD Fail History         : Disabled
Host Request Reordering          : Enabled
Auto Detect BackPlane Enabled    : SGPIO/i2c SEP
Load Balance Mode                : Auto
Any Offline VD Cache Preserved   : No

                Capabilities
                ================
RAID Level Supported             : RAID0, RAID1, RAID5, RAID6, RAID10, RAID50, RAID60
Supported Drives                 : SAS, SATA

Allowed Mixing:

Mix In Enclosure Allowed

                Status
                ================
ECC Bucket Count                 : 0

                Limitations
                ================
Max Arms Per VD         : 32 
Max Spans Per VD        : 8 
Max Arrays              : 128 
Max Number of VDs       : 64 
Max Parallel Commands   : 1008 
Max SGE Count           : 80 
Max Data Transfer Size  : 8192 sectors 
Max Strips PerIO        : 42 
Min Stripe Size         : 8kB
Max Stripe Size         : 1024kB

                Device Present
                ================
Virtual Drives    : 2 
  Degraded        : 0 
  Offline         : 0 
Physical Devices  : 5 
  Disks           : 4 
  Critical Disks  : 0 
  Failed Disks    : 0 

                Supported Adapter Operations
                ================
Rebuild Rate                    : Yes
CC Rate                         : Yes
BGI Rate                        : Yes
Reconstruct Rate                : Yes
Patrol Read Rate                : Yes
Alarm Control                   : Yes
Cluster Support                 : No
BBU                             : Yes
Spanning                        : Yes
Dedicated Hot Spare             : Yes
Revertible Hot Spares           : No
Foreign Config Import           : Yes
Self Diagnostic                 : Yes
Allow Mixed Redundancy on Array : No
Global Hot Spares               : Yes
Deny SCSI Passthrough           : No
Deny SMP Passthrough            : No
Deny STP Passthrough            : No

                Supported VD Operations
                ================
Read Policy          : Yes
Write Policy         : Yes
IO Policy            : Yes
Access Policy        : Yes
Disk Cache Policy    : Yes
Reconstruction       : Yes
Deny Locate          : No
Deny CC              : No

                Supported PD Operations
                ================
Force Online                            : Yes
Force Offline                           : Yes
Force Rebuild                           : Yes
Deny Force Failed                       : No
Deny Force Good/Bad                     : No
Deny Missing Replace                    : No
Deny Clear                              : No
Deny Locate                             : No
Disable Copyback                        : No
Enable Copyback on SMART                : No
Enable Copyback to SSD on SMART error   : No

                Error Counters
                ================
Memory Correctable Errors   : 0 
Memory Uncorrectable Errors : 0 

                Cluster Information
                ================
Cluster Permitted     : No
Cluster Active        : No

                Default Settings
                ================
Phy Polarity                     : 0 
Phy PolaritySplit                : 0 
Background Rate                  : 30 
Stripe Size                      : 64kB
Flush Time                       : 4 seconds
Write Policy                     : WB
Read Policy                      : None
Cache When BBU Bad               : Disabled
Cached IO                        : No
SMART Mode                       : Mode 6
Alarm Disable                    : No
Coercion Mode                    : 128MB
ZCR Config                       : Unknown
Dirty LED Shows Drive Activity   : No
BIOS Continue on Error           : No
Spin Down Mode                   : None
Allowed Device Type              : SAS/SATA Mix
Allow Mix In Enclosure           : Yes
Allow HDD SAS/SATA Mix In VD     : No
Allow SSD SAS/SATA Mix In VD     : No
Allow HDD/SAS Mix In VD          : No
Allow SATA In Cluster            : No
Max Chained Enclosures           : 1 
Disable Ctrl-R                   : No
Enable Web BIOS                  : No
Direct PD Mapping                : Yes
BIOS Enumerate VDs               : Yes
Restore Hot Spare on Insertion   : No
Expose Enclosure Devices         : No
Maintain PD Fail History         : No
Disable Puncturing               : No
Zero Based Enclosure Enumeration : Yes
PreBoot CLI Enabled              : No
LED Show Drive Activity          : No
Cluster Disable                  : Yes
SAS Disable                      : No
Auto Detect BackPlane Enable     : SGPIO/i2c SEP
Delay during POST                : 0 

Exit Code: 0x00
EOF
parse_lsi_megaraid_adapter_info $TMPDIR/in > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
