#!/bin/bash

# This test file must be ran by util/test-bash-functions.

TESTS=2

TEST_NAME="df-mount-001.txt"
cat <<EOF > $TMPDIR/expected
  Filesystem                     Size Used Type  Opts Mountpoint
  /dev/mapper/vg_ginger-lv_root  454G   6% ext4  rw   /
  /dev/sda1                      194M  31% ext4  rw   /boot
  tmpfs                          2.0G   1% tmpfs rw   /dev/shm
EOF
parse_filesystems "samples/df-mount-001.txt" "Linux" > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="df-mount-002.txt"
cat <<EOF > $TMPDIR/expected
  Filesystem                          Size Used Type  Opts Mountpoint
  /dev/mapper/VolGroup00-LogVol00      62G  56% ext3  rw   /
  /dev/mapper/VolGroup01-MySQLData00   67G  20% ext3  rw   /var/lib/mysql
  /dev/sda3                           190M  11% ext3  rw   /boot
  tmpfs                               7.9G   0% tmpfs rw   /dev/shm
EOF
parse_filesystems "samples/df-mount-002.txt" "Linux" > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
