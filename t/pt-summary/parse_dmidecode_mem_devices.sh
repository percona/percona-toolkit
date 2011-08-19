#!/bin/bash

TESTS=5

TEST_NAME="dmidecode-001.txt"
cat <<EOF > $TMPDIR/expected
  Locator   Size     Speed             Form Factor   Type          Type Detail
  ========= ======== ================= ============= ============= ===========
  SODIMM0   2048 MB  800 MHz           SODIMM        Other         Synchronous
  SODIMM1   2048 MB  800 MHz           SODIMM        Other         Synchronous
EOF
parse_dmidecode_mem_devices samples/dmidecode-001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="dmidecode-002.tx"
cat <<EOF > $TMPDIR/expected
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
parse_dmidecode_mem_devices samples/dmidecode-002.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="dmidecode-003.txt"
cat <<EOF > $TMPDIR/expected
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
parse_dmidecode_mem_devices samples/dmidecode-003.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="dmidecode-004.txt"
cat <<EOF > $TMPDIR/expected
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
parse_dmidecode_mem_devices samples/dmidecode-004.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected

TEST_NAME="dmidecode-005.txt"
cat <<EOF > $TMPDIR/expected
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
parse_dmidecode_mem_devices samples/dmidecode-005.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
