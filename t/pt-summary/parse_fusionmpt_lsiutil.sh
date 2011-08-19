#!/bin/bash

TESTS=3

TEST_NAME="lsiutil-001.txt"
cat <<EOF > $TMPDIR/expected

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
parse_fusionmpt_lsiutil samples/lsiutil-001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="lsiutil-002.txt"
cat <<EOF > $TMPDIR/expected

  /proc/mpt/ioc0    LSI Logic SAS1064E B3    MPT 105   Firmware 011e0000   IOC 0
   B___T___L  Type       Vendor   Product          Rev      SASAddress     PhyNum
   0   1   0  Disk       LSILOGIC Logical Volume   3000  
  Hidden RAID Devices:
   B___T    Device       Vendor   Product          Rev      SASAddress     PhyNum
   0   2  PhysDisk 0     IBM-ESXS ST9300603SS   F  B536  5000c5001d784329     1
   0   3  PhysDisk 1     IBM-ESXS MBD2300RC        SB17  500000e113c17152     0
EOF
parse_fusionmpt_lsiutil samples/lsiutil-002.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="lsiutil-003.txt"
cat <<EOF > $TMPDIR/expected

  /proc/mpt/ioc0    LSI Logic SAS1064E B3    MPT 105   Firmware 011e0000   IOC 0
   B___T___L  Type       Vendor   Product          Rev      SASAddress     PhyNum
   0   1   0  Disk       LSILOGIC Logical Volume   3000  
  Hidden RAID Devices:
   B___T    Device       Vendor   Product          Rev      SASAddress     PhyNum
   0   2  PhysDisk 0     IBM-ESXS MBD2300RC        SB17  500000e113c00ed2     1
   0   3  PhysDisk 1     IBM-ESXS MBD2300RC        SB17  500000e113c17ee2     0
EOF
parse_fusionmpt_lsiutil samples/lsiutil-003.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
