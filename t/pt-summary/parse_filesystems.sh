#!/bin/bash

TESTS=4
TMPDIR=$TEST_TMPDIR

TEST_NAME="df-mount-003.txt Linux"
cat <<EOF > $TMPDIR/expected
  Filesystem  Size Used Type  Opts Mountpoint
  /dev/sda1    99M  13% ext3  rw   /boot
  /dev/sda2   540G  89% ext3  rw   /
  tmpfs        48G   0% tmpfs rw   /dev/shm
EOF
parse_filesystems samples/df-mount-003.txt Linux > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="df-mount-004.txt Linux"
cat <<EOF > $TMPDIR/expected
  Filesystem  Size Used Type        Opts              Mountpoint
  /dev/sda1   9.9G  34% ext3        rw                /
  /dev/sdb    414G   1% ext3        rw                /mnt
  none        7.6G   0% devpts      rw,gid=5,mode=620 /dev/shm
  none        7.6G   0% tmpfs       rw                /dev/shm
  none        7.6G   0% binfmt_misc rw                /dev/shm
  none        7.6G   0% proc        rw                /dev/shm
  none        7.6G   0% sysfs       rw                /dev/shm
EOF
parse_filesystems samples/df-mount-004.txt Linux > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="df-mount-005.txt Linux"
cat <<EOF > $TMPDIR/expected
  Filesystem                         Size Used Type  Opts       Mountpoint
  /dev/cciss/c0d0p1                   99M  24% ext3  rw         /boot
  /dev/mapper/VolGroup00-LogVol00    194G  58% ext3  rw         /
  /dev/mapper/VolGroup00-mysql_log   191G   4% ext3  rw         /data/mysql-log
  /dev/mapper/VolGroup01-mysql_data 1008G  44% ext3  rw,noatime /data/mysql-data
  tmpfs                               48G   0% tmpfs rw         /dev/shm
EOF
parse_filesystems samples/df-mount-005.txt Linux > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="df-mount-006.txt FreeBSD"
cat <<EOF > $TMPDIR/expected
  Filesystem   Size Used Type  Opts                Mountpoint
  /dev/ad0s1a  496M  32% ufs   local               /
  /dev/ad0s1d  1.1G   1% ufs   local, soft-updates /var
  /dev/ad0s1e  496M   0% ufs   local, soft-updates /tmp
  /dev/ad0s1f   17G   9% ufs   local, soft-updates /usr
  devfs        1.0K 100% devfs local               /dev
EOF
parse_filesystems samples/df-mount-006.txt FreeBSD > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
