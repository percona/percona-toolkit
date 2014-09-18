#!/usr/bin/env bash

plan 54

. "$LIB_DIR/alt_cmds.sh"
. "$LIB_DIR/log_warn_die.sh"
. "$LIB_DIR/parse_options.sh"
. "$LIB_DIR/summary_common.sh"
. "$LIB_DIR/report_formatting.sh"
. "$LIB_DIR/report_system_info.sh"

PT_TMPDIR="$TEST_PT_TMPDIR"
PATH="$PATH:$PERCONA_TOOLKIT_SANDBOX/bin"
TOOL="pt-summary"

samples="$PERCONA_TOOLKIT_BRANCH/t/pt-summary/samples"
NAME_VAL_LEN=12

# parse_proc_cpuinfo

cat <<EOF > "$PT_TMPDIR/expected"
  Processors | physical = 1, cores = 2, virtual = 2, hyperthreading = no
      Speeds | 2x1300.000
      Models | 2xGenuine Intel(R) CPU U7300 @ 1.30GHz
      Caches | 2x3072 KB
EOF

parse_proc_cpuinfo "$samples/proc_cpuinfo001.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "parse_proc_cpuinfo, proc_cpuinfo001.txt"

cat <<EOF > "$PT_TMPDIR/expected"
  Processors | physical = 1, cores = 1, virtual = 2, hyperthreading = yes
      Speeds | 2x1000.000
      Models | 2xIntel(R) Atom(TM) CPU N455 @ 1.66GHz
      Caches | 2x512 KB
EOF

parse_proc_cpuinfo "$samples/proc_cpuinfo002.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "parse_proc_cpuinfo, proc_cpuinfo002.txt"

# parse_ethtool
cat <<EOF > "$PT_TMPDIR/in"
Settings for eth0:
   Supported ports: [ TP MII ]
   Supported link modes:   10baseT/Half 10baseT/Full 
                           100baseT/Half 100baseT/Full 
   Supports auto-negotiation: Yes
   Advertised link modes:  10baseT/Half 10baseT/Full 
                           100baseT/Half 100baseT/Full 
   Advertised pause frame use: Symmetric Receive-only
   Advertised auto-negotiation: Yes
   Speed: 10Mb/s
   Duplex: Half
   Port: MII
   PHYAD: 0
   Transceiver: internal
   Auto-negotiation: on
   Supports Wake-on: pumbg
   Wake-on: d
   Current message level: 0x00000033 (51)
                drv probe ifdown ifup
   Link detected: no
EOF

cat <<EOF > "$PT_TMPDIR/expected"
  Device    Speed     Duplex
  ========= ========= =========
  eth0       10Mb/s     Half      
EOF

parse_ethtool "$PT_TMPDIR/in" > "$PT_TMPDIR/got"
no_diff \
   "$PT_TMPDIR/expected" \
   "$PT_TMPDIR/got" \
   "parse_ethtool works"

cat <<EOF > "$PT_TMPDIR/in"
Settings for eth0:
   Supported ports: [ TP MII ]
   Supported link modes:   10baseT/Half 10baseT/Full 
                           100baseT/Half 100baseT/Full 
   Supports auto-negotiation: Yes
   Advertised link modes:  10baseT/Half 10baseT/Full 
                           100baseT/Half 100baseT/Full 
   Advertised pause frame use: Symmetric Receive-only
   Advertised auto-negotiation: Yes
   Speed: 10Mb/s
   Duplex: Half
   Port: MII
   PHYAD: 0
   Transceiver: internal
   Auto-negotiation: on
   Supports Wake-on: pumbg
   Wake-on: d
   Current message level: 0x00000033 (51)
                drv probe ifdown ifup
   Link detected: no
Settings for eth4:
   Supported ports: [ TP MII ]
   Supported link modes:   10baseT/Half 10baseT/Full 
                           100baseT/Half 100baseT/Full 
   Supports auto-negotiation: Yes
   Advertised link modes:  10baseT/Half 10baseT/Full 
                           100baseT/Half 100baseT/Full 
   Advertised pause frame use: Symmetric Receive-only
   Advertised auto-negotiation: Yes
   Speed: 100Mb/s
   Duplex: Full
   Port: MII
   PHYAD: 0
   Transceiver: internal
   Auto-negotiation: on
   Supports Wake-on: pumbg
   Wake-on: d
   Current message level: 0x00000033 (51)
                drv probe ifdown ifup
   Link detected: no
EOF

cat <<EOF > "$PT_TMPDIR/expected"
  Device    Speed     Duplex
  ========= ========= =========
  eth0       10Mb/s     Half      
  eth4       100Mb/s    Full      
EOF

parse_ethtool "$PT_TMPDIR/in" > "$PT_TMPDIR/got"
no_diff \
   "$PT_TMPDIR/expected" \
   "$PT_TMPDIR/got" \
   "parse_ethtool works if there are multiple devices"

# parse_netstat

cat <<EOF > $PT_TMPDIR/expected
  Connections from remote IP addresses
    192.168.243.72      1
    192.168.243.81      2
  Connections to local IP addresses
    192.168.243.71      3
  Connections to top 10 local ports
    3306                3
  States of connections
    ESTABLISHED         4
    LISTEN             15
EOF
parse_netstat "$samples/netstat-001.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "parse_netstat, netstat-001.txt"

cat <<EOF > "$PT_TMPDIR/expected"
  Connections from remote IP addresses
    10.14.82.196      175
    10.14.82.200       10
    10.14.82.202       45
    10.17.85.70        60
    10.17.85.72         1
    10.17.85.74         2
    10.17.85.86       225
    10.17.85.88        80
    10.17.85.90        40
    10.17.85.92         1
    10.17.85.100       25
    10.17.85.104       20
    10.36.34.66       300
    10.36.34.68       300
  Connections to local IP addresses
    10.17.85.70       175
    10.17.146.20     1250
  Connections to top 10 local ports
    3306             1250
    44811               1
    44816               1
    44817               1
    44820               1
    44822               1
    44824               1
    44825               1
    54446               1
  States of connections
    ESTABLISHED       150
    LISTEN             15
    TIME_WAIT        1250
EOF
parse_netstat "$samples/netstat-002.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "parse_netstat, netstat-002.txt"

cat <<EOF > "$PT_TMPDIR/expected"
  Connections from remote IP addresses
    10.8.0.12           6
    10.8.0.14           2
    10.8.0.65           1
    10.8.0.76          25
    10.8.0.77           1
    192.168.5.77        2
  Connections to local IP addresses
    10.8.0.75          35
  Connections to top 10 local ports
    22                  1
    3306               25
    37570               1
    51071               1
    51072               1
    51073               1
    51074               1
    52300               1
    60757               1
  States of connections
    ESTABLISHED        30
    LISTEN              3
    TIME_WAIT           3
EOF

parse_netstat "$samples/netstat-003.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "parse_netstat, netstat-003.txt"

# parse_lsi_megaraid

cat <<EOF > "$PT_TMPDIR/expected"
         BBU | 100% Charged, Temperature 18C, isSOHGood=Yes
EOF

cat <<EOF > "$PT_TMPDIR/in"
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
parse_lsi_megaraid_bbu_status "$PT_TMPDIR/in" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected"

# ############################################################################
cat <<EOF > "$PT_TMPDIR/expected"

  PhysiclDev Type State   Errors Vendor  Model        Size
  ========== ==== ======= ====== ======= ============ ===========
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
EOF

cat <<EOF > "$PT_TMPDIR/in"
                                     
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
parse_lsi_megaraid_devices "$PT_TMPDIR/in" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected"


# ############################################################################
cat <<EOF > "$PT_TMPDIR/expected"

  PhysiclDev Type State   Errors Vendor  Model        Size
  ========== ==== ======= ====== ======= ============ ===========
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST373455SS   70007MB
EOF

cat <<EOF > "$PT_TMPDIR/in"
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
parse_lsi_megaraid_devices "$PT_TMPDIR/in" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected"

# ############################################################################
cat <<EOF > "$PT_TMPDIR/expected"

  VirtualDev Size      RAID Level Disks SpnDpth Stripe Status  Cache
  ========== ========= ========== ===== ======= ====== ======= =========
  0(no name) 69376MB   1 (1-0-0)      2     1-1   64kB Optimal WB, no RA
  1(no name) 69376MB   1 (1-0-0)      2     1-1   64kB Optimal WB, no RA
EOF

cat <<EOF > "$PT_TMPDIR/in"
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
parse_lsi_megaraid_virtual_devices "$PT_TMPDIR/in" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected"

# ############################################################################
cat <<EOF > "$PT_TMPDIR/expected"

  VirtualDev Size      RAID Level Disks SpnDpth Stripe Status  Cache
  ========== ========= ========== ===== ======= ====== ======= =========
  0(no name) 69376MB   1 (1-0-0)      2      1-   64kB Optimal WB, no RA
  1(no name) 69376MB   1 (1-0-0)      2      1-   64kB Optimal WB, no RA
EOF

cat <<EOF > "$PT_TMPDIR/in"
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
parse_lsi_megaraid_virtual_devices "$PT_TMPDIR/in" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected"


# ############################################################################
cat <<EOF > "$PT_TMPDIR/expected"
       Model | PERC 6/i Integrated, PCIE interface, 8 ports
       Cache | 256MB Memory, BBU Present
EOF

parse_lsi_megaraid_adapter_info "$samples/MegaCli64_AdpAllInfo_aALL001.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected"

# Launchpad 886223
cat <<EOF > "$PT_TMPDIR/expected"

  VirtualDev Size      RAID Level Disks SpnDpth Stripe Status  Cache
  ========== ========= ========== ===== ======= ====== ======= =========
  0(no name)  135.5 GB 0 (:-1-0)      2 Depth-2  64 KB Optimal WB, no RA
EOF
parse_lsi_megaraid_virtual_devices "$PERCONA_TOOLKIT_BRANCH/t/pt-summary/samples/MegaCli64_LdPdInfo_aALL_886223" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "Bug 886223"

# parse_hpacucli

cat <<EOF > "$PT_TMPDIR/expected"
      logicaldrive 1 (136.7 GB, RAID 1, OK)
      physicaldrive 1I:1:1 (port 1I:box 1:bay 1, SAS, 146 GB, OK)
      physicaldrive 1I:1:2 (port 1I:box 1:bay 2, SAS, 146 GB, OK)
EOF

cat <<EOF > "$PT_TMPDIR/in"

Smart Array P400i in Slot 0 (Embedded)    (sn: PH73MU7325     )

   array A (SAS, Unused Space: 0 MB)


      logicaldrive 1 (136.7 GB, RAID 1, OK)

      physicaldrive 1I:1:1 (port 1I:box 1:bay 1, SAS, 146 GB, OK)
      physicaldrive 1I:1:2 (port 1I:box 1:bay 2, SAS, 146 GB, OK)

EOF
parse_hpacucli "$PT_TMPDIR/in" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected"

parse_hpacucli "$samples/hpaculi-003.txt" > "$PT_TMPDIR/got"
is \
   "$(cat "$PT_TMPDIR/got")" \
   "" \
   "parse_hpacucli, hpaculi-003.txt"

# parse_fusionmpt_lsiutil

cat <<EOF > "$PT_TMPDIR/expected"

  /proc/mpt/ioc0    LSI Logic SAS1068E B3    MPT 105   Firmware 00192f00   IOC 0
   B___T___L  Type       Vendor   Product          Rev      SASAddress     PhyNum
   0   0   0  Disk       Dell     VIRTUAL DISK     1028  
   0   2   0  Disk       Dell     VIRTUAL DISK     1028  
   0   8   0  EnclServ   DP       BACKPLANE        1.05  510240805f4feb00     8
  Hidden RAID Devices:
   B___T    Device       Vendor   Product          Rev      SASAddress     PhyNum
   0   1  PhysDisk 0     SEAGATE  ST373455SS       S52A  5000c50012a8ac61     1
   0   9  PhysDisk 1     SEAGATE  ST373455SS       S52A  5000c50012a8a24d     0
   0   3  PhysDisk 2     SEAGATE  ST3146855SS      S52A  5000c500130fcaed     3
   0  10  PhysDisk 3     SEAGATE  ST3146855SS      S52A  5000c500131093f5     2
EOF
parse_fusionmpt_lsiutil "$samples/lsiutil-001.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "lsiutil-001.txt"

cat <<EOF > "$PT_TMPDIR/expected"

  /proc/mpt/ioc0    LSI Logic SAS1064E B3    MPT 105   Firmware 011e0000   IOC 0
   B___T___L  Type       Vendor   Product          Rev      SASAddress     PhyNum
   0   1   0  Disk       LSILOGIC Logical Volume   3000  
  Hidden RAID Devices:
   B___T    Device       Vendor   Product          Rev      SASAddress     PhyNum
   0   2  PhysDisk 0     IBM-ESXS ST9300603SS   F  B536  5000c5001d784329     1
   0   3  PhysDisk 1     IBM-ESXS MBD2300RC        SB17  500000e113c17152     0
EOF
parse_fusionmpt_lsiutil "$samples/lsiutil-002.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "lsiutil-002.txt"

cat <<EOF > "$PT_TMPDIR/expected"

  /proc/mpt/ioc0    LSI Logic SAS1064E B3    MPT 105   Firmware 011e0000   IOC 0
   B___T___L  Type       Vendor   Product          Rev      SASAddress     PhyNum
   0   1   0  Disk       LSILOGIC Logical Volume   3000  
  Hidden RAID Devices:
   B___T    Device       Vendor   Product          Rev      SASAddress     PhyNum
   0   2  PhysDisk 0     IBM-ESXS MBD2300RC        SB17  500000e113c00ed2     1
   0   3  PhysDisk 1     IBM-ESXS MBD2300RC        SB17  500000e113c17ee2     0
EOF
parse_fusionmpt_lsiutil "$samples/lsiutil-003.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "lsiutil-003.txt"

# parse_free_minus_b

cat <<EOF > "$PT_TMPDIR/expected"
       Total | 3.9G
        Free | 1.4G
        Used | physical = 2.5G, swap allocated = 4.9G, swap used = 0.0, virtual = 2.5G
     Buffers | 131.8M
      Caches | 1.9G
       Dirty | 60 kB
EOF

cat <<EOF > "$PT_TMPDIR/in"
             total       used       free     shared    buffers     cached
Mem:    4182048768 2653696000 1528352768          0  138240000 2060787712
-/+ buffers/cache:  454668288 3727380480
Swap:   5284814848          0 5284814848
MemTotal:        4084040 kB
MemFree:         2390720 kB
Buffers:          121868 kB
Cached:          1155116 kB
SwapCached:            0 kB
Active:           579712 kB
Inactive:         941436 kB
Active(anon):     244720 kB
Inactive(anon):    40572 kB
Active(file):     334992 kB
Inactive(file):   900864 kB
Unevictable:          48 kB
Mlocked:              48 kB
HighTotal:       3251848 kB
HighFree:        1837740 kB
LowTotal:         832192 kB
LowFree:          552980 kB
SwapTotal:       5144572 kB
SwapFree:        5144572 kB
Dirty:                60 kB
Writeback:             0 kB
AnonPages:        244264 kB
Mapped:            84452 kB
Shmem:             41140 kB
Slab:             133548 kB
SReclaimable:     107672 kB
SUnreclaim:        25876 kB
KernelStack:        2264 kB
PageTables:         7740 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:     7186592 kB
Committed_AS:    1192140 kB
VmallocTotal:     122880 kB
VmallocUsed:       32276 kB
VmallocChunk:      65120 kB
HardwareCorrupted:     0 kB
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
DirectMap4k:       10232 kB
DirectMap2M:      897024 kB
EOF
parse_free_minus_b "$PT_TMPDIR/in" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "parse_free_minus_b"

# Bug 993436: Memory: Total reports M when it should say G
cat <<EOF > "$PT_TMPDIR/expected"
       Total | 1010.5M
        Free | 784.4M
        Used | physical = 226.1M, swap allocated = 2.0G, swap used = 0.0, virtual = 226.1M
     Buffers | 48.8M
      Caches | 122.2M
       Dirty | 152 kB
EOF
parse_free_minus_b "$T_DIR/pt-summary/samples/Linux/002/memory" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "parse_free_minus_b (bug 993436)"

# parse_filesystems

cat <<EOF > $PT_TMPDIR/expected
  Filesystem  Size Used Type  Opts Mountpoint
  /dev/sda1    99M  13% ext3  rw   /boot
  /dev/sda2   540G  89% ext3  rw   /
  tmpfs        48G   0% tmpfs rw   /dev/shm
EOF
parse_filesystems "$samples/df-mount-003.txt" "Linux" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "df-mount-003.txt Linux"

cat <<EOF > $PT_TMPDIR/expected
  Filesystem  Size Used Type        Opts              Mountpoint
  /dev/sda1   9.9G  34% ext3        rw                /
  /dev/sdb    414G   1% ext3        rw                /mnt
  none        7.6G   0% devpts      rw,gid=5,mode=620 /dev/shm
  none        7.6G   0% tmpfs       rw                /dev/shm
  none        7.6G   0% binfmt_misc rw                /dev/shm
  none        7.6G   0% proc        rw                /dev/shm
  none        7.6G   0% sysfs       rw                /dev/shm
EOF
parse_filesystems "$samples/df-mount-004.txt" "Linux" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "df-mount-004.txt Linux"

cat <<EOF > $PT_TMPDIR/expected
  Filesystem                         Size Used Type  Opts       Mountpoint
  /dev/cciss/c0d0p1                   99M  24% ext3  rw         /boot
  /dev/mapper/VolGroup00-LogVol00    194G  58% ext3  rw         /
  /dev/mapper/VolGroup00-mysql_log   191G   4% ext3  rw         /data/mysql-log
  /dev/mapper/VolGroup01-mysql_data 1008G  44% ext3  rw,noatime /data/mysql-data
  tmpfs                               48G   0% tmpfs rw         /dev/shm
EOF
parse_filesystems "$samples/df-mount-005.txt" "Linux" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "df-mount-005.txt Linux"

cat <<EOF > $PT_TMPDIR/expected
  Filesystem   Size Used Type  Opts                Mountpoint
  /dev/ad0s1a  496M  32% ufs   local               /
  /dev/ad0s1d  1.1G   1% ufs   local, soft-updates /var
  /dev/ad0s1e  496M   0% ufs   local, soft-updates /tmp
  /dev/ad0s1f   17G   9% ufs   local, soft-updates /usr
  devfs        1.0K 100% devfs local               /dev
EOF
parse_filesystems "$samples/df-mount-006.txt" "FreeBSD" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "df-mount-006.txt FreeBSD"

# parse_ip_s_link

cat <<EOF > "$PT_TMPDIR/expected"
  interface  rx_bytes rx_packets  rx_errors   tx_bytes tx_packets  tx_errors
  ========= ========= ========== ========== ========== ========== ==========
  lo          3000000      25000          0    3000000      25000          0
  eth0      175000000   30000000          0  125000000     900000          0
  wlan0      50000000      80000          0   20000000      90000          0
  vboxnet0          0          0          0          0          0          0
EOF
parse_ip_s_link "$samples/ip-s-link-001.txt" > $PT_TMPDIR/got
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "ip-s-link-001.txt"

cat <<EOF > "$PT_TMPDIR/expected"
  interface  rx_bytes rx_packets  rx_errors   tx_bytes tx_packets  tx_errors
  ========= ========= ========== ========== ========== ========== ==========
  lo       3500000000  350000000          0 3500000000  350000000          0
  eth0     1750000000 1250000000          0 3500000000  700000000          0
  eth1     1250000000   60000000          0  900000000   50000000          0
  sit0              0          0          0          0          0          0
EOF
parse_ip_s_link "$samples/ip-s-link-002.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "ip-s-link-002.txt"

cat <<EOF > "$PT_TMPDIR/expected"
  interface  rx_bytes rx_packets  rx_errors   tx_bytes tx_packets  tx_errors
  ========= ========= ========== ========== ========== ========== ==========
  lo         25000000     300000          0   25000000     300000          0
  eth0              0          0          0          0          0          0
  wlan0             0          0          0          0          0          0
  virbr0            0          0          0          0          0          0
EOF
parse_ip_s_link "$samples/ip-s-link-003.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "ip-s-link-003.txt"

# parse_fdisk

cat <<EOF > "$PT_TMPDIR/expected"
Device       Type      Start        End               Size
============ ==== ========== ========== ==================
/dev/dm-0    Disk                             494609104896
/dev/dm-1    Disk                               5284823040
/dev/sda     Disk                             500107862016
/dev/sda1    Part          1         26          205632000
/dev/sda2    Part         26      60801       499891392000
EOF
parse_fdisk "$samples/fdisk-01.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "parse_fdisk"

# parse_ethernet_controller_lspci

cat <<EOF > $PT_TMPDIR/expected
  Controller | Broadcom Corporation NetXtreme II BCM5708 Gigabit Ethernet (rev 12)
  Controller | Broadcom Corporation NetXtreme II BCM5708 Gigabit Ethernet (rev 12)
EOF
parse_ethernet_controller_lspci "$samples/lspci-001.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected"

# parse_dmidecode_mem_devices

cat <<EOF > $PT_TMPDIR/expected
  Locator   Size     Speed             Form Factor   Type          Type Detail
  ========= ======== ================= ============= ============= ===========
  SODIMM0   2048 MB  800 MHz           SODIMM        Other         Synchronous
  SODIMM1   2048 MB  800 MHz           SODIMM        Other         Synchronous
EOF
parse_dmidecode_mem_devices "$samples/dmidecode-001.txt" > $PT_TMPDIR/got
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmidecode-001.tx"

cat <<EOF > "$PT_TMPDIR/expected"
  Locator   Size     Speed             Form Factor   Type          Type Detail
  ========= ======== ================= ============= ============= ===========
  DIMM1     2048 MB  667 MHz (1.5 ns)  {OUT OF SPEC} {OUT OF SPEC} Synchronous
  DIMM2     2048 MB  667 MHz (1.5 ns)  {OUT OF SPEC} {OUT OF SPEC} Synchronous
  DIMM3     2048 MB  667 MHz (1.5 ns)  {OUT OF SPEC} {OUT OF SPEC} Synchronous
  DIMM4     2048 MB  667 MHz (1.5 ns)  {OUT OF SPEC} {OUT OF SPEC} Synchronous
  DIMM5     2048 MB  667 MHz (1.5 ns)  {OUT OF SPEC} {OUT OF SPEC} Synchronous
  DIMM6     2048 MB  667 MHz (1.5 ns)  {OUT OF SPEC} {OUT OF SPEC} Synchronous
  DIMM7     2048 MB  667 MHz (1.5 ns)  {OUT OF SPEC} {OUT OF SPEC} Synchronous
  DIMM8     2048 MB  667 MHz (1.5 ns)  {OUT OF SPEC} {OUT OF SPEC} Synchronous
EOF
parse_dmidecode_mem_devices "$samples/dmidecode-002.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmidecode-002.tx"

cat <<EOF > "$PT_TMPDIR/expected"
  Locator   Size     Speed             Form Factor   Type          Type Detail
  ========= ======== ================= ============= ============= ===========
            1024 kB  33 MHz            Other         Flash         Non-Volatile
  D5        4096 MB  1066 MHz          DIMM          Other         Other   
  D8        4096 MB  1066 MHz          DIMM          Other         Other   
  D0        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D0        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D1        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D1        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D2        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D2        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D3        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D3        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D4        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D4        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D5        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D6        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D6        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D7        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D7        {EMPTY}  1333 MHz          DIMM          Other         Other   
  D8        {EMPTY}  1333 MHz          DIMM          Other         Other   
EOF
parse_dmidecode_mem_devices "$samples/dmidecode-003.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmidecode-003.txt"

cat <<EOF > "$PT_TMPDIR/expected"
  Locator   Size     Speed             Form Factor   Type          Type Detail
  ========= ======== ================= ============= ============= ===========
  DIMM_A2   4096 MB  1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Synchronous
  DIMM_A3   4096 MB  1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Synchronous
  DIMM_A5   4096 MB  1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Synchronous
  DIMM_A6   4096 MB  1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Synchronous
  DIMM_B2   4096 MB  1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Synchronous
  DIMM_B3   4096 MB  1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Synchronous
  DIMM_B5   4096 MB  1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Synchronous
  DIMM_B6   4096 MB  1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Synchronous
  DIMM_A1   {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Synchronous
  DIMM_A4   {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Synchronous
  DIMM_B1   {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Synchronous
  DIMM_B4   {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Synchronous
EOF
parse_dmidecode_mem_devices "$samples/dmidecode-004.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmidecode-004.txt"

cat <<EOF > "$PT_TMPDIR/expected"
  Locator   Size     Speed             Form Factor   Type          Type Detail
  ========= ======== ================= ============= ============= ===========
  P1-DIMM1A 16384 MB 1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Other   
  P1-DIMM2A 16384 MB 1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Other   
  P1-DIMM3A 16384 MB 1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Other   
  P2-DIMM1A 16384 MB 1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Other   
  P2-DIMM2A 16384 MB 1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Other   
  P2-DIMM3A 16384 MB 1066 MHz (0.9 ns) DIMM          {OUT OF SPEC} Other   
            4096 kB  33 MHz (30.3 ns)  Other         Flash         Non-Volatile
  P1-DIMM1B {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Other   
  P1-DIMM1C {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Other   
  P1-DIMM2B {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Other   
  P1-DIMM2C {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Other   
  P1-DIMM3B {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Other   
  P1-DIMM3C {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Other   
  P2-DIMM1B {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Other   
  P2-DIMM1C {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Other   
  P2-DIMM2B {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Other   
  P2-DIMM2C {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Other   
  P2-DIMM3B {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Other   
  P2-DIMM3C {EMPTY}  Unknown           DIMM          {OUT OF SPEC} Other   
EOF
parse_dmidecode_mem_devices "$samples/dmidecode-005.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmidecode-005.txt"

cat <<EOF > "$PT_TMPDIR/expected"
  Locator   Size     Speed             Form Factor   Type          Type Detail
  ========= ======== ================= ============= ============= ===========
  DIMM 1    8192 MB  1600 MHz          SODIMM        DDR3          Synchronous
  DIMM 2    8192 MB  1600 MHz          SODIMM        DDR3          Synchronous
EOF
parse_dmidecode_mem_devices "$samples/dmidecode-006.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmidecode-006.txt"


# parse_arcconf

cat <<EOF > "$PT_TMPDIR/expected"
       Specs | Adaptec 3405, SAS/SATA, 128 MB cache, Optimal
     Battery | 99%, 3d1h11m remaining, Optimal

  LogicalDev Size      RAID Disks Stripe Status  Cache
  ========== ========= ==== ===== ====== ======= =======
  raid10     279800 MB   10     4 256 KB Optimal On (WB)

  PhysiclDev State   Speed         Vendor  Model        Size        Cache
  ========== ======= ============= ======= ============ =========== =======
  Hard drive Online  SAS 3.0 Gb/s  SEAGATE ST3146855SS  140014 MB   On (WB)
  Hard drive Online  SAS 3.0 Gb/s  SEAGATE ST3146356SS  140014 MB   On (WB)
  Hard drive Online  SAS 3.0 Gb/s  SEAGATE ST3146356SS  140014 MB   On (WB)
  Hard drive Online  SAS 3.0 Gb/s  SEAGATE ST3146855SS  140014 MB   On (WB)
EOF

cat <<EOF > "$PT_TMPDIR/in"
# /usr/StorMan/arcconf getconfig 1
Controllers found: 1
----------------------------------------------------------------------
Controller information
----------------------------------------------------------------------
   Controller Status                        : Optimal
   Channel description                      : SAS/SATA
   Controller Model                         : Adaptec 3405
   Controller Serial Number                 : 8C16103E017
   Physical Slot                            : 1
   Temperature                              : 35 C/ 95 F (Normal)
   Installed memory                         : 128 MB
   Copyback                                 : Disabled
   Background consistency check             : Disabled
   Automatic Failover                       : Enabled
   Global task priority                     : High
   Stayawake period                         : Disabled
   Spinup limit internal drives             : 0
   Spinup limit external drives             : 0
   Defunct disk drive count                 : 0
   Logical devices/Failed/Degraded          : 1/0/0
   --------------------------------------------------------
   Controller Version Information
   --------------------------------------------------------
   BIOS                                     : 5.2-0 (17304)
   Firmware                                 : 5.2-0 (17304)
   Driver                                   : 1.1-5 (2461)
   Boot Flash                               : 5.2-0 (17304)
   --------------------------------------------------------
   Controller Battery Information
   --------------------------------------------------------
   Status                                   : Optimal
   Over temperature                         : No
   Capacity remaining                       : 99 percent
   Time remaining (at current draw)         : 3 days, 1 hours, 11 minutes

----------------------------------------------------------------------
Logical device information
----------------------------------------------------------------------
Logical device number 0
   Logical device name                      : raid10
   RAID level                               : 10
   Status of logical device                 : Optimal
   Size                                     : 279800 MB
   Stripe-unit size                         : 256 KB
   Read-cache mode                          : Enabled
   Write-cache mode                         : Enabled (write-back)
   Write-cache setting                      : Enabled (write-back) when protected by battery
   Partitioned                              : Unknown
   Protected by Hot-Spare                   : No
   Bootable                                 : Yes
   Failed stripes                           : No
   Power settings                           : Disabled
   --------------------------------------------------------
   Logical device segment information
   --------------------------------------------------------
   Group 0, Segment 0                       : Present (0,0) 3LN6552C00009903T8E4
   Group 0, Segment 1                       : Present (0,1) 3QN26HL400009009KZ0Q
   Group 1, Segment 0                       : Present (0,2) 3QN1S2AN00009001XVFZ
   Group 1, Segment 1                       : Present (0,3) 3LN648WZ00009903T916


----------------------------------------------------------------------
Physical Device information
----------------------------------------------------------------------
      Device #0
         Device is a Hard drive
         State                              : Online
         Supported                          : Yes
         Transfer Speed                     : SAS 3.0 Gb/s
         Reported Channel,Device(T:L)       : 0,0(0:0)
         Reported Location                  : Connector 0, Device 0
         Vendor                             : SEAGATE
         Model                              : ST3146855SS
         Firmware                           : 0002
         Serial number                      : 3LN6552C00009903T8E4
         World-wide name                    : 5000C5000C4DDBB8
         Size                               : 140014 MB
         Write Cache                        : Enabled (write-back)
         FRU                                : None
         S.M.A.R.T.                         : No
      Device #1
         Device is a Hard drive
         State                              : Online
         Supported                          : Yes
         Transfer Speed                     : SAS 3.0 Gb/s
         Reported Channel,Device(T:L)       : 0,1(1:0)
         Reported Location                  : Connector 0, Device 1
         Vendor                             : SEAGATE
         Model                              : ST3146356SS
         Firmware                           : 0005
         Serial number                      : 3QN26HL400009009KZ0Q
         World-wide name                    : 5000C50016F5E66C
         Size                               : 140014 MB
         Write Cache                        : Enabled (write-back)
         FRU                                : None
         S.M.A.R.T.                         : No
      Device #2
         Device is a Hard drive
         State                              : Online
         Supported                          : Yes
         Transfer Speed                     : SAS 3.0 Gb/s
         Reported Channel,Device(T:L)       : 0,2(2:0)
         Reported Location                  : Connector 0, Device 2
         Vendor                             : SEAGATE
         Model                              : ST3146356SS
         Firmware                           : 0005
         Serial number                      : 3QN1S2AN00009001XVFZ
         World-wide name                    : 5000C50016F5EF4C
         Size                               : 140014 MB
         Write Cache                        : Enabled (write-back)
         FRU                                : None
         S.M.A.R.T.                         : No
      Device #3
         Device is a Hard drive
         State                              : Online
         Supported                          : Yes
         Transfer Speed                     : SAS 3.0 Gb/s
         Reported Channel,Device(T:L)       : 0,3(3:0)
         Reported Location                  : Connector 0, Device 3
         Vendor                             : SEAGATE
         Model                              : ST3146855SS
         Firmware                           : 0002
         Serial number                      : 3LN648WZ00009903T916
         World-wide name                    : 5000C5000C4DEA60
         Size                               : 140014 MB
         Write Cache                        : Enabled (write-back)
         FRU                                : None
         S.M.A.R.T.                         : No


Command completed successfully.

EOF
parse_arcconf "$PT_TMPDIR/in" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected"

cat <<EOF > "$PT_TMPDIR/expected"
       Specs | Adaptec 3405, SAS/SATA, 128 MB cache, Optimal
     Battery | 99%, 3d1h11m remaining, Optimal

  LogicalDev Size      RAID Disks Stripe Status  Cache
  ========== ========= ==== ===== ====== ======= =======
  Raid10-A   571392 MB   10     4 256 KB Optimal On (WB)

  PhysiclDev State   Speed         Vendor  Model        Size        Cache
  ========== ======= ============= ======= ============ =========== =======
  Hard drive Online  SAS 3.0 Gb/s  SEAGATE ST3300655SS  286102 MB   On (WB)
  Hard drive Online  SAS 3.0 Gb/s  SEAGATE ST3300655SS  286102 MB   On (WB)
  Hard drive Online  SAS 3.0 Gb/s  SEAGATE ST3300655SS  286102 MB   On (WB)
  Hard drive Online  SAS 3.0 Gb/s  SEAGATE ST3300655SS  286102 MB   On (WB)
EOF
parse_arcconf "$samples/arcconf-002.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "arcconf-002.txt"

# Launchpad 917781, parse_arcconf doesn't work with ZMM
# https://bugs.launchpad.net/percona-toolkit/+bug/917781
cat <<EOF > "$PT_TMPDIR/expected"
       Specs | Adaptec 5405Z, SAS/SATA, 512 MB cache, Optimal
     Battery | ZMM Optimal

  LogicalDev Size      RAID Disks Stripe Status  Cache
  ========== ========= ==== ===== ====== ======= =======
  RAID10-A   571382 MB   10     4 256 KB Optimal On (WB)

  PhysiclDev State   Speed         Vendor  Model        Size        Cache
  ========== ======= ============= ======= ============ =========== =======
  Hard drive Full rpm,Powered off SATA 3.0 Gb/s WDC     WD3000HLFS-0 286168 MB   On (WB)
  Hard drive Full rpm,Powered off SATA 3.0 Gb/s WDC     WD3000HLFS-0 286168 MB   On (WB)
  Hard drive Full rpm,Powered off SATA 3.0 Gb/s WDC     WD3000HLFS-0 286168 MB   On (WB)
  Hard drive Full rpm,Powered off SATA 3.0 Gb/s WDC     WD3000HLFS-0 286168 MB   On (WB)
EOF

parse_arcconf "$samples/arcconf-004_917781.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "Bug 917781"

# Launchpad 900285, ${var/ /} doesn't work in sh
# https://bugs.launchpad.net/percona-toolkit/+bug/900285
cat <<EOF > "$PT_TMPDIR/expected"
       Specs | Adaptec 5805Z, SAS/SATA, 512 MB cache, Optimal
     Battery | ZMM Optimal

  LogicalDev Size      RAID Disks Stripe Status  Cache
  ========== ========= ==== ===== ====== ======= =======
  RAID10-A   121790 MB   10     4 256 KB Optimal On (WB)
  RAID1-A    285686 MB    1     0        Optimal On (WB)

  PhysiclDev State   Speed         Vendor  Model        Size        Cache
  ========== ======= ============= ======= ============ =========== =======
  Hard drive Full rpm,Powered off SATA 3.0 Gb/s INTEL   SSDSA2SH064G1GC 61057 MB    On (WB)
  Hard drive Full rpm,Powered off SATA 3.0 Gb/s INTEL   SSDSA2SH064G1GC 61057 MB    On (WB)
  Hard drive Full rpm,Powered off SATA 3.0 Gb/s INTEL   SSDSA2SH064G1GC 61057 MB    On (WB)
  Hard drive Full rpm,Powered off SATA 3.0 Gb/s INTEL   SSDSA2SH064G1GC 61057 MB    On (WB)
  Hard drive Full rpm,Powered off SAS 3.0 Gb/s  SEAGATE ST3300657SS  286102 MB   On (WB)
  Hard drive Full rpm,Powered off SAS 3.0 Gb/s  SEAGATE ST3300657SS  286102 MB   On (WB)
EOF
parse_arcconf "$samples/arcconf-003_900285.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "Bug 900285"

# parse_uptime

cat <<EOF > "$PT_TMPDIR/in"
 15:10:14 up 1 day, 15:08, 11 users,  load average: 0.18, 0.09, 0.08
EOF
is \
   "$( parse_uptime "$PT_TMPDIR/in" )" \
   "1 day, 15:08, 11 users,  load average: 0.18, 0.09, 0.08" \
   "parse_uptime works with Ubuntu's uptime"

cat <<EOF > "$PT_TMPDIR/in"
 some weird format etc 1 day, 15:08, 11 users,  load average: 0.18, 0.09, 0.08
EOF
is \
   "$( parse_uptime "$PT_TMPDIR/in" )" \
   " some weird format etc 1 day, 15:08, 11 users,  load average: 0.18, 0.09, 0.08" \
   "parse_uptime returns uptime as-if if it doesn't contain an 'up'"

# parse_lvs

is \
   "$(format_lvs "" "")" \
   "Unable to collect information" \
   "format_lvs has a meaningful error message if all goes wrong"


echo "Pretending to be an lvs dump" > "$PT_TMPDIR/in"
is \
   "$(format_lvs "$PT_TMPDIR/in" "")" \
   "Pretending to be an lvs dump" \
   "format_lvs dumps the file passed in"

# report_system_summary
parse_options "$BIN_DIR/pt-summary"

cat <<EOF > "$PT_TMPDIR/expected"
    Hostname | 
      Uptime | 57 mins, 1 user, load averages: 0.16, 0.03, 0.07
    Platform | FreeBSD
     Release | 8.2-RELEASE
      Kernel | 199506
Architecture | CPU = 32-bit, OS = 32-bit
 Virtualized | No virtualization detected
# Processor ##################################################
  Processors | virtual = 1
      Speeds | 2109
      Models | AMD Athlon(tm) 64 X2 Dual Core Processor 4000+
# Memory #####################################################
       Total | 499.4M
     Virtual | 511.9M
        Used | 66.4M
     UsedRSS | 17.7M
# Mounted Filesystems ########################################
  Filesystem   Size Used Type    Opts                Mountpoint
  /dev/ad0s1a  620M  30% ufs     local               /
  /dev/ad0s1d  1.3G   0% ufs     local, soft-updates /var
  /dev/ad0s1e  341M   0% ufs     local, soft-updates /tmp
  /dev/ad0s1f  3.3G  32% ufs     local, soft-updates /usr
  /dev/da0s1   3.8G   0% msdosfs local               /mnt/usb
  devfs        1.0K 100% devfs   local, multilabel   /dev
  procfs       4.0K 100% procfs  local               /proc
# RAID Controller ############################################
  Controller | No RAID controller detected
# Top Processes ##############################################
  PID USERNAME  THR PRI NICE   SIZE    RES STATE    TIME   WCPU COMMAND
23318 root        1  76    0  3632K  1744K wait     0:00  0.98% sh
  447 root        1  44    0  1888K   584K select   0:00  0.00% devd
  945 root        1  44    0  4672K  2336K pause    0:00  0.00% csh
  556 root        1  44    0  3352K  1264K select   0:00  0.00% syslogd
  848 root        1  44    0  6092K  3164K select   0:00  0.00% sendmail
  859 root        1  44    0  3380K  1308K nanslp   0:00  0.00% cron
  931 root        1  44    0  3816K  1724K wait     0:00  0.00% login
  937 root        1  76    0  3352K  1096K ttyin    0:00  0.00% getty
  934 root        1  76    0  3352K  1096K ttyin    0:00  0.00% getty
# Notable Processes ##########################################
  PID    OOM    COMMAND
    ?      ?    sshd doesn't appear to be running
# Simplified and fuzzy rounded vmstat (wait please) ##########
 procs      memory      page                    disks     faults         cpu
 r b w     avm    fre   flt  re  pi  po    fr  sr ad0 da0   in   sy   cs us sy id
 1 0 0   63720  339504  1158   0   0   0  1022   0   0   0  246 1201  336 22 15 63
 0 0 0   58164  339792  7924   0   0   0  6663   0   4   3  242 5829  744 15 71 14
 0 0 0   58164  339792     0   0   0   0     0   0   0   0  230  107  231  0  9 91
 0 0 0   58164  339792     0   0   0   0     0   0   0   0  230  107  229  0  3 97
 0 0 0   58164  339792     0   0   0   0     0   0   0   0  231  115  229  0  5 95
# The End ####################################################
EOF
report_system_summary "$samples/BSD/freebsd_001" | tail -n +3 > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "report_system_summary works with samples from a FreeBSD box"

cat <<EOF > "$PT_TMPDIR/expected"
    Hostname | 
      Uptime | 43 mins, 2 users, load averages: 0.00, 0.00, 0.00
    Platform | NetBSD
     Release | 5.1.2
      Kernel | 501000200
Architecture | CPU = 32-bit, OS = 32-bit
 Virtualized | No virtualization detected
# Processor ##################################################
  Processors | physical = 1, cores = 0, virtual = 1, hyperthreading = no
      Speeds | 1x2178.48
      Models | 1xAMD Athlon(tm) 64 X2 Dual Core Processor 4000+
      Caches | 
# Memory #####################################################
       Total | 127.6M
        User | 127.2M
        Swap | 64.5M
     UsedRSS | 10.6M
# Mounted Filesystems ########################################
  Filesystem  Size Used Type Opts                                                             Mountpoint
  /dev/sd0e   3.8G   0% yp   dev/sd0e 3.8G 17M 3.7G 0% /mnt/usb on /mnt/usb type msdos (local /mnt/usb
  /dev/wd0a   1.8G  30% yp   dev/wd0a 1.8G 545M 1.2G 30% / on / type ffs (local               /
  kernfs      1.0K 100% yp   ernfs 1.0K 1.0K 0B 100% /kern on /kern type kernfs (local        /kern
  procfs      4.0K 100% yp   rocfs 4.0K 4.0K 0B 100% /proc on /proc type procfs (local        /proc
  ptyfs       1.0K 100% yp   tyfs 1.0K 1.0K 0B 100% /dev/pts on /dev/pts type ptyfs (local    /dev/pts
# RAID Controller ############################################
  Controller | No RAID controller detected
# Top Processes ##############################################
  PID USERNAME PRI NICE   SIZE   RES STATE      TIME   WCPU    CPU COMMAND
    0 root     124    0     0K   20M syncer     0:01  0.00%  0.00% [system]
 3922 root      43    0  2976K  984K CPU        0:00  0.00%  0.00% top
  277 root      85    0  5592K 2232K wait       0:00  0.00%  0.00% login
  279 root      85    0  5592K 2164K wait       0:00  0.00%  0.00% login
 3501 root      85    0  2836K 1396K pause      0:00  0.00%  0.00% ksh
  284 root      85    0  2960K 1192K wait       0:00  0.00%  0.00% sh
 1957 root      85    0  2960K 1164K ttyraw     0:00  0.00%  0.00% sh
  116 root      85    0  2940K 1016K kqueue     0:00  0.00%  0.00% syslogd
  272 root      85    0  2920K  940K ttyraw     0:00  0.00%  0.00% getty
# Notable Processes ##########################################
  PID    OOM    COMMAND
    ?      ?    sshd doesn't appear to be running
# Simplified and fuzzy rounded vmstat (wait please) ##########
 procs    memory      page                       disks   faults      cpu
 r b w    avm    fre  flt  re  pi   po   fr   sr w0 c0   in   sy  cs us sy id
 2 0 0  78624  21544  103   0   0    0    0    0  6  0  113  154  33  0  2 98
 2 0 0  78652  21260 12425  0   0    0    0    0  0  0   92 6208 355 12 84  4
 0 0 0  78564  21364 1208   0   0    0    0    0  0  0   98  806  43  2  9 89
 0 0 0  78564  21364    0   0   0    0    0    0  0  0  101   11   9  0 0 100
 0 0 0  78564  21364    0   0   0    0    0    0  0  0  101   11  10  0 0 100
# The End ####################################################
EOF
report_system_summary "$samples/BSD/netbsd_001" | tail -n +3 > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "netbsd_001"

cat <<EOF > "$PT_TMPDIR/expected"
    Hostname | openbsd.my.domain
      Uptime | 1:14, 1 user, load averages: 0.44, 0.20, 0.16
    Platform | OpenBSD
     Release | 5.0
      Kernel | 201111
Architecture | CPU = 32-bit, OS = 32-bit
 Virtualized | No virtualization detected
# Processor ##################################################
  Processors | 1
      Speeds | 2111
      Models | AMD 
# Memory #####################################################
       Total | 255.5M
        User | 255.5M
        Swap | 81.1M
     UsedRSS | 5.3M
# Mounted Filesystems ########################################
  Filesystem  Size Used Type Opts                                               Mountpoint
  /dev/sd0i   3.8G   0% yp   long                                               /mnt/usb
  /dev/wd0a   788M   6% yp   dev/wd0a 788M 42.5M 706M 6% / on / type ffs (local /
  /dev/wd0d   893M  48% yp   nodev                                              /usr
  /dev/wd0e   252M  37% yp   nodev, nosuid                                      /home
# RAID Controller ############################################
  Controller | No RAID controller detected
# Top Processes ##############################################
  PID USERNAME PRI NICE  SIZE   RES STATE     WAIT      TIME    CPU COMMAND
22422 root      18    0  888K 1012K sleep     pause     0:00  0.93% sh
20216 _pflogd    4    0  528K  312K sleep     bpf       0:01  0.00% pflogd
22982 root       2    0 1372K 1956K sleep     select    0:00  0.00% sendmail
26829 root      18    0  544K  532K sleep     pause     0:00  0.00% ksh
17299 _syslogd   2    0  524K  752K sleep     poll      0:00  0.00% syslogd
 7254 root       2    0  508K  872K idle      select    0:00  0.00% cron
    1 root      10    0  544K  324K idle      wait      0:00  0.00% init
28237 root       2    0  500K  696K idle      netio     0:00  0.00% syslogd
30259 root       3    0  408K  812K idle      ttyin     0:00  0.00% getty
# Notable Processes ##########################################
  PID    OOM    COMMAND
    ?      ?    sshd doesn't appear to be running
# Simplified and fuzzy rounded vmstat (wait please) ##########
 procs    memory       page                    disks    traps          cpu
 r b w    avm     fre  flt  re  pi  po  fr  sr wd0 cd0  int   sys   cs us sy id
 2 1 0   7608  191356   66   0   0   0   0   0   2   0  231   108   14  0  1 99
 1 1 0   7804  191192 9916   0   0   0   0   0   0   0  234 14726  315  9 90  1
 1 0 0   7600  191360 9461   0   0   0   0   0   0   0  256 14435  285  6 94  0
 0 0 0   7496  191456 1272   0   0   0   0   0   0   0  256  1973   50  2 12 85
 0 0 0   7496  191456   11   0   0   0   0   0   0   0  230    23   12  0  0 100
# The End ####################################################
EOF
report_system_summary "$samples/BSD/openbsd_001" | tail -n +3  > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "openbsd_001"

cat <<EOF > "$PT_TMPDIR/expected"
    Hostname | hugmeir
      Uptime | 1 day, 15:14,  5 users,  load average: 0.00, 0.06, 0.07
      System | Quanta; UW3; vTBD (Other)
 Service Tag | 123456789
    Platform | Linux
     Release | Ubuntu 11.10 (oneiric)
      Kernel | 3.0.0-16-generic
Architecture | CPU = 32-bit, OS = 32-bit
   Threading | NPTL 2.13
     SELinux | No SELinux detected
 Virtualized | No virtualization detected
# Processor ##################################################
  Processors | physical = 1, cores = 1, virtual = 2, hyperthreading = yes
      Speeds | 1x1000.000, 1x1666.000
      Models | 2xIntel(R) Atom(TM) CPU N455 @ 1.66GHz
      Caches | 2x512 KB
# Memory #####################################################
       Total | 2.0G
        Free | 477.3M
        Used | physical = 1.5G, swap allocated = 2.0G, swap used = 0.0, virtual = 1.5G
     Buffers | 194.9M
      Caches | 726.8M
       Dirty | 144 kB
     UsedRSS | 1.1G
  Swappiness | 60
 DirtyPolicy | 20, 10
  Locator   Size     Speed             Form Factor   Type          Type Detail
  ========= ======== ================= ============= ============= ===========
  DIMM0     2048 MB  667 MHz (1.5 ns)  SODIMM        DDR2          Synchronous
# Mounted Filesystems ########################################
  Filesystem  Size Used Type       Opts                                                                                              Mountpoint
  /dev/sda7   333G  12% ext4       rw,errors=remount-ro,commit=0                                                                     /
  /dev/sdb1   3.8G   1% vfat       rw,nosuid,nodev,uid=1000,gid=1000,shortname=mixed,dmask=0077,utf8=1,showexec,flush,uhelper=udisks /media/PENDRIVE
  none       1002M   1% tmpfs      rw,noexec,nosuid,nodev,size=5242880                                                               /run/shm
  none       1002M   1% tmpfs      rw,nosuid,nodev                                                                                   /run/shm
  none       1002M   1% debugfs    rw                                                                                                /run/shm
  none       1002M   1% securityfs rw                                                                                                /run/shm
  none        5.0M   0% tmpfs      rw,noexec,nosuid,nodev,size=5242880                                                               /run/lock
  none        5.0M   0% tmpfs      rw,nosuid,nodev                                                                                   /run/lock
  none        5.0M   0% debugfs    rw                                                                                                /run/lock
  none        5.0M   0% securityfs rw                                                                                                /run/lock
  tmpfs       401M   1% tmpfs      rw,noexec,nosuid,size=10%,mode=0755                                                               /run
  udev        995M   1% devtmpfs   rw,mode=0755                                                                                      /dev
# Disk Schedulers And Queue Size #############################
         sda | [cfq] 128
         sdb | [cfq] 128
# Disk Partioning ############################################
Device       Type      Start        End               Size
============ ==== ========== ========== ==================
/dev/sda     Disk                             500107862016
/dev/sda1    Part       2048     206847          104857088
/dev/sda2    Part     206848   12494847         6291455488
/dev/sda3    Part   12494848  207808587       100000634368
/dev/sda4    Part  207810558  976771071       393707782656
/dev/sda5    Part  207810560  259807667        26622518784
/dev/sda6    Part  972603392  976771071         2133851648
/dev/sda7    Part  259809280  968421375       362809392640
/dev/sda8    Part  968423424  972591103         2133851648
/dev/sdb     Disk                               4041211904
/dev/sdb1    Part         63    7892991         4041179136
# Kernel Inode State #########################################
dentry-state | 78471 67588 45 0  0  0
     file-nr | 9248  0  203574
    inode-nr | 70996 10387
# LVM Volumes ################################################
  No volume groups found
# LVM Volume Groups ##########################################
Unable to collect information
# RAID Controller ############################################
  Controller | No RAID controller detected
# Network Config #############################################
  Controller | Realtek Semiconductor Co., Ltd. RTL8101E/RTL8102E PCI Express Fast Ethernet controller (rev 02)
 FIN Timeout | 60
  Port Range | 61000
# Interface Statistics #######################################
  interface  rx_bytes rx_packets  rx_errors   tx_bytes tx_packets  tx_errors
  ========= ========= ========== ========== ========== ========== ==========
  lo         25000000     350000          0   25000000     350000          0
  eth0              0          0          0          0          0          0
  wlan0             0          0          0          0          0          0
  virbr0            0          0          0          0          0          0
# Network Connections ########################################
  Connections from remote IP addresses
  Connections to local IP addresses
  Connections to top 10 local ports
  States of connections
    LISTEN              4
# Top Processes ##############################################
  PID USER      PR  NI  VIRT  RES  SHR S %CPU %MEM    TIME+  COMMAND
 1548 hugmeir   20   0  122m  14m  10m S    2  0.7   1:44.97 gnome-settings-
 1567 hugmeir   20   0  257m  88m  22m S    2  4.4  83:35.58 compiz
 4455 hugmeir   20   0  283m  30m  21m S    2  1.5  30:42.87 knotify4
17394 hugmeir   20   0  118m  37m  26m S    2  1.9   0:29.35 kwrite
30819 root      20   0  2824 1144  844 R    2  0.1   0:00.03 top
    1 root      20   0  3328 1912 1248 S    0  0.1   0:01.55 init
    2 root      20   0     0    0    0 S    0  0.0   0:00.07 kthreadd
    3 root      20   0     0    0    0 S    0  0.0   0:05.54 ksoftirqd/0
    6 root      RT   0     0    0    0 S    0  0.0   0:00.00 migration/0
# Notable Processes ##########################################
  PID    OOM    COMMAND
    ?      ?    sshd doesn't appear to be running
  305    -17    udevd
29745    -17    udevd
29746    -17    udevd
# Simplified and fuzzy rounded vmstat (wait please) ##########
  procs  ---swap-- -----io---- ---system---- --------cpu--------
   r  b    si   so    bi    bo     ir     cs  us  sy  il  wa  st
   2  0     0    0     2     1    150     50   4   1  95   0    
   0  0     0    0     0     8    900   2250  28  26  46   0    
   0  0     0    0     0     0    200    200   1   0  99   0    
   1  0     0    0     0   150    225    225   1   1  95   3    
   0  0     0    0     0   150    250    250   1   0  99   0    
# The End ####################################################
EOF

report_system_summary "$samples/Linux/001" | tail -n +3 > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "Linux/001 (Ubuntu)"

report_system_summary "$samples/Linux/002" | tail -n +3 > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$samples/Linux/output_002.txt" "Linux/002 (CentOS 5.7, as root)"

report_system_summary "$samples/Linux/003" | tail -n +3 > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$samples/Linux/output_003.txt" "Linux/003 (CentOS 5.7, as non-root)"

# pt-summary to show information about Fusion-io cards
# https://bugs.launchpad.net/percona-toolkit/+bug/952722

cat <<EOF > "$PT_TMPDIR/expected"
  fio Driver | 2.3.1 build 123
 ioDrive Duo | Fusion-io ioDrive Duo 640GB, Product Number:FS3-202-321-CS SN:40123
            fct0 | Attached as 'fioa' (block device)
                 | Fusion-io ioDrive Duo 640GB, Product Number:FS3-202-321-CS SN:06665
                 | Firmware v5.0.7, rev 101971
                 | Internal temperature: 47.7 degC, max 48.2 degC
                 | Media status: Healthy; Reserves: 100.00%, warn at 10.00%
            fct1 | Attached as 'fiob' (block device)
                 | Fusion-io ioDrive Duo 640GB, Product Number:FS3-202-321-CS SN:06478
                 | Firmware v5.0.7, rev 101971
                 | Internal temperature: 42.8 degC, max 47.7 degC
                 | Media status: Healthy; Reserves: 100.00%, warn at 10.00%
EOF

report_fio_minus_a "$samples/Linux/004/fio-001" > "$PT_TMPDIR/got"
no_diff \
   "$PT_TMPDIR/got" \
   "$PT_TMPDIR/expected" \
   "report_fio_minus_a works with one adapter and two modules"

cat <<EOF > "$PT_TMPDIR/expected"
  fio Driver | 2.3.1 build 123
     ioDrive | Fusion-io ioDrive 720GB, Product Number:FS1-003-721-CS SN:122210
            fct0 | Attached as 'fioa' (block device)
                 | Fusion-io ioDrive 720GB, Product Number:FS1-003-721-CS SN:122210
                 | Firmware v5.0.5, rev 43674
                 | Internal temperature: 53.2 degC, max 62.5 degC
                 | Media status: Healthy; Reserves: 100.00%, warn at 10.00%
EOF

report_fio_minus_a "$samples/Linux/004/fio-002" > "$PT_TMPDIR/got"

no_diff \
   "$PT_TMPDIR/got" \
   "$PT_TMPDIR/expected" \
   "report_fio_minus_a works with one adapter and one module"

cat <<EOF > "$PT_TMPDIR/expected"
  fio Driver | 2.3.1 build 123
 ioDrive Duo | Fusion-io ioDrive Duo 640GB, Product Number:FS3-202-321-CS SN:40123
            fct0 | Attached as 'fioa' (block device)
                 | Fusion-io ioDrive Duo 640GB, Product Number:FS3-202-321-CS SN:06665
                 | Firmware v5.0.7, rev 101971
                 | Internal temperature: 47.7 degC, max 48.2 degC
                 | Media status: Healthy; Reserves: 100.00%, warn at 10.00%
            fct1 | Attached as 'fiob' (block device)
                 | Fusion-io ioDrive Duo 640GB, Product Number:FS3-202-321-CS SN:06478
                 | Firmware v5.0.7, rev 101971
                 | Internal temperature: 42.8 degC, max 47.7 degC
                 | Media status: Healthy; Reserves: 100.00%, warn at 10.00%
 ioDrive Duo | Fusion-io ioDrive Duo 640GB, Product Number:FS3-202-321-CS SN:40124
            fct2 | Attached as 'fioc' (block device)
                 | Fusion-io ioDrive Duo 640GB, Product Number:FS3-202-321-CS SN:06665
                 | Firmware v5.0.7, rev 101971
                 | Internal temperature: 47.7 degC, max 48.2 degC
                 | Media status: Healthy; Reserves: 100.00%, warn at 10.00%
            fct3 | Attached as 'fiod' (block device)
                 | Fusion-io ioDrive Duo 640GB, Product Number:FS3-202-321-CS SN:06478
                 | Firmware v5.0.7, rev 101971
                 | Internal temperature: 42.8 degC, max 47.7 degC
                 | Media status: Healthy; Reserves: 100.00%, warn at 10.00%
EOF

report_fio_minus_a "$samples/Linux/004/fio-003" > "$PT_TMPDIR/got"

no_diff \
   "$PT_TMPDIR/got" \
   "$PT_TMPDIR/expected" \
   "report_fio_minus_a works with two adapters, each with two modules"

cat <<EOF > "$PT_TMPDIR/expected"
  fio Driver | 3.1.5 build 126
Dual Controller Adapter | Fusion-io ioDrive2 Duo 2.41TB, Product Number:F01-001-2T41-CS-0001, SN:1150D0121, FIO SN:1150D0121
            fct0 | Attached as 'fioa' (block device)
                 | SN:1150D0121-1121
                 | Firmware v7.0.0, rev 107322 Public
                 | Internal temperature: 51.68 degC, max 58.08 degC
                 | Reserve space status: Healthy; Reserves: 100.00%, warn at 10.00%
                 | Rated PBW: 17.00 PB, 98.41% remaining
            fct1 | Attached as 'fiob' (block device)
                 | SN:1150D0121-1111
                 | Firmware v7.0.0, rev 107322 Public
                 | Internal temperature: 46.76 degC, max 51.19 degC
                 | Reserve space status: Healthy; Reserves: 100.00%, warn at 10.00%
                 | Rated PBW: 17.00 PB, 98.95% remaining
EOF

report_fio_minus_a "$samples/Linux/004/fio-004" > "$PT_TMPDIR/got"

no_diff \
   "$PT_TMPDIR/got" \
   "$PT_TMPDIR/expected" \
   "report_fio_minus_a works with Dual Controller Adapter / ioMemory modules"
