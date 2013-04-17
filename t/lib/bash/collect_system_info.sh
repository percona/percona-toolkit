#!/usr/bin/env bash

plan 44

PT_TMPDIR="$TEST_PT_TMPDIR"
PATH="$PATH:$PERCONA_TOOLKIT_SANDBOX/bin"
TOOL="pt-summary"

. "$LIB_DIR/log_warn_die.sh"
. "$LIB_DIR/alt_cmds.sh"
. "$LIB_DIR/parse_options.sh"
. "$LIB_DIR/summary_common.sh"
. "$LIB_DIR/parse_options.sh"
. "$LIB_DIR/collect_system_info.sh"

# Prefix (with path) for the collect files.
p="$PT_TMPDIR/collect_mysql_info"
samples="$PERCONA_TOOLKIT_BRANCH/t/pt-summary/samples"

mkdir "$p"

parse_options "$BIN_DIR/pt-summary" --sleep 1

setup_commands

collect_system_data "$p"

p2="$PT_TMPDIR/collect_mysql_info2"
mkdir "$p2"
touch "$p2/some_empty_file"
collect_system_data "$p2"

cmd_ok "test ! -e \"$p2/some_empty_file\"" "collect_system_data removes empty files before exiting"

cat <<EOF > "$PT_TMPDIR/expected"
Fusion-MPT SAS
EOF
find_raid_controller_lspci "$samples/lspci-001.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "lspci-001.txt"

cat <<EOF > "$PT_TMPDIR/expected"
LSI Logic Unknown
EOF
find_raid_controller_lspci "$samples/lspci-002.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "lspci-002.txt"

cat <<EOF > "$PT_TMPDIR/expected"
AACRAID
EOF
find_raid_controller_lspci "$samples/lspci-003.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "lspci-003.txt"

cat <<EOF > "$PT_TMPDIR/expected"
LSI Logic MegaRAID SAS
EOF
find_raid_controller_lspci "$samples/lspci-004.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "lspci-004.txt"

cat <<EOF > "$PT_TMPDIR/expected"
Fusion-MPT SAS
EOF
find_raid_controller_lspci "$samples/lspci-005.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "lspci-005.txt"

cat <<EOF > "$PT_TMPDIR/expected"
HP Smart Array
EOF
find_raid_controller_lspci "$samples/lspci-006.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "lspci-006.txt"

# find_raid_controller_dmesg

cat <<EOF > "$PT_TMPDIR/expected"
Fusion-MPT SAS
EOF
find_raid_controller_dmesg "$samples/dmesg-001.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmesg-001.txt"

cat <<EOF > "$PT_TMPDIR/expected"
AACRAID
EOF
find_raid_controller_dmesg "$samples/dmesg-002.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmesg-002.txt"

cat <<EOF > "$PT_TMPDIR/expected"
LSI Logic MegaRAID SAS
EOF
find_raid_controller_dmesg "$samples/dmesg-003.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmesg-003.txt"

cat <<EOF > "$PT_TMPDIR/expected"
AACRAID
EOF
find_raid_controller_dmesg "$samples/dmesg-004.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmesg-004.txt"

cat <<EOF > "$PT_TMPDIR/expected"
Fusion-MPT SAS
EOF
find_raid_controller_dmesg "$samples/dmesg-005.txt" > "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmesg-005.txt"

# TODO is this right?
cat <<EOF > "$PT_TMPDIR/expected"
EOF
find_raid_controller_dmesg "$samples/dmesg-006.txt" > "$PT_TMPDIR/got"
cat "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmesg-006.txt"

# TODO is this right?
cat <<EOF > "$PT_TMPDIR/expected"
EOF
find_raid_controller_dmesg "$samples/dmesg-007.txt" > "$PT_TMPDIR/got"
cat "$PT_TMPDIR/got"
no_diff "$PT_TMPDIR/got" "$PT_TMPDIR/expected" "dmesg-007.txt"

# raid_controller

rm "$PT_TMPDIR/raid_controller_outfile.tmp" 2>/dev/null
raid_controller "" "" > "$PT_TMPDIR/raid_controller_outfile.tmp"

is \
   "$(get_var raid_controller "$PT_TMPDIR/raid_controller_outfile.tmp")" \
   "No RAID controller detected" \
   "raid_controller has a sane default"

rm "$PT_TMPDIR/raid_controller_outfile.tmp" 2>/dev/null
raid_controller "" "$samples/lspci-001.txt" > "$PT_TMPDIR/raid_controller_outfile.tmp"
is \
   "$(get_var raid_controller "$PT_TMPDIR/raid_controller_outfile.tmp")" \
   "Fusion-MPT SAS" \
   "raid_controller gets the correct result from an lspci file"

rm "$PT_TMPDIR/raid_controller_outfile.tmp" 2>/dev/null
raid_controller "$samples/dmesg-004.txt" "" > "$PT_TMPDIR/raid_controller_outfile.tmp"
is \
   "$(get_var raid_controller "$PT_TMPDIR/raid_controller_outfile.tmp")" \
   "AACRAID" \
   "...Or from a dmseg file"

# find_virtualization_dmesg

i=1
for expected in "" "" "" "" "" "Xen" "VirtualBox"; do
   find_virtualization_dmesg "$samples/dmesg-00$i.txt" > "$PT_TMPDIR/got"
   is "$(cat "$PT_TMPDIR/got")" "$expected" "dmesg-00$i.txt"
   i=$(($i + 1))
done

# linux_exclusive_collection

fake_command () {
   local cmd="$1"
   local output="$2"

   printf "#!/usr/bin/env bash\necho \"${output}\"\n" > "$PT_TMPDIR/${cmd}_replacement"
   chmod +x "$PT_TMPDIR/${cmd}_replacement"
   eval "CMD_$(echo $cmd | tr '[a-z]' '[A-Z]' | tr '\-' '_')=\"$PT_TMPDIR/${cmd}_replacement\""
}

test_linux_exclusive_collection () {
   local dir="$1"

   # First, let's try what happens if none of the commands are available
   local CMD_LVS=""
   local CMD_VGS=""
   local CMD_NETSTAT=""
   local PT_SUMMARY_SKIP=""

   mkdir "$dir/1"
   if [ -e "$dir/sysctl" ]; then
      cp "$dir/sysctl" "$dir/1/"
   fi
   linux_exclusive_collection "$dir/1"

   is \
      "$(ls "$dir/1" | grep 'lvs\|vgs\|netstat' )" \
      "" \
      'linux_exclusive_collection: If a command isnt available, doesnt create spurious files'

   local i=1
   for f in lvs vgs netstat; do
      fake_command "$f" "ok $i"
      i=$(($i + 1))
   done
   
   mkdir "$dir/2"
   if [ -e "$dir/sysctl" ]; then
      cp "$dir/sysctl" "$dir/2/"
   fi
   linux_exclusive_collection "$dir/2"

   is \
      "$(ls "${dir}/2" | grep 'lvs\|vgs\|netstat' | sort | xargs echo )" \
      "lvs lvs.stderr netstat vgs" \
      "linux_exclusive_collection: And works as expected if they are there"

   local i=1
   for f in lvs vgs netstat; do
      is \
         "$(cat "${dir}/2/${f}")" \
         "ok $i" \
         "linux_exclusive_collection: output for $f is correct"
      i=$(($i + 1))
   done
}

platform="$(get_var platform "$p/summary")"

if [ "$platform" = "Linux" ]; then
   mkdir "$PT_TMPDIR/linux_data"
   if [ -e "$p/sysctl" ]; then
      cp "$p/sysctl" "$PT_TMPDIR/linux_data/sysctl"
   fi
   test_linux_exclusive_collection "$PT_TMPDIR/linux_data"
   rm -rf "$PT_TMPDIR/linux_data"
else
   skip 1 5 "Tests exclusive for Linux"
fi

# propietary_raid_controller

test_propietary_raid_controller () {
   local dir="$1"

   local CMD_ARCCONF=""
   local CMD_HPACUCLI=""
   local CMD_MEGACLI64=""

   local controller=""
   mkdir "$dir/1"
   for controller in "AACRAID" "HP Smart Array" "LSI Logic MegaRAID SAS"; do
      rm "$dir/1/summary" 2>/dev/null
      touch "$dir/1/summary"
      propietary_raid_controller "$dir/1/raid-controller" "$dir/1/summary" "$dir/1" "$controller"
      is \
         "$(get_var "internal::raid_opt" "$dir/1/summary")" \
         0 \
         "propietary_raid_controller: correct raid_opt default for $controller"

      cmd_ok \
         "grep -q 'RAID controller software not found' \"$dir/1/raid-controller\"" \
         "propietary_raid_controller: correct default for $controller if the command isn't available"
   done
   
   mkdir "$dir/2"
   fake_command arcconf "ok arcconf"
   propietary_raid_controller "$dir/2/raid-controller" "$dir/2/summary" "$dir/2" "AACRAID"
   is \
      "$(get_var "internal::raid_opt" "$dir/2/summary")" \
      1 \
      "propietary_raid_controller: correct raid_opt default for $controller when arcconf is there"

   is \
      "$(cat "$dir/2/raid-controller")" \
      "ok arcconf" \
      "AACRAID calls arcconf"
}

mkdir "$PT_TMPDIR/raid_controller"
test_propietary_raid_controller "$PT_TMPDIR/raid_controller"


# notable_processes_info
(
   sleep 50000
) 2>/dev/null &
forked_pid="$!"

if [ -w /proc/$forked_pid/oom_adj ] \
      && echo "-17" > /proc/$forked_pid/oom_adj 2>/dev/null; then

   notable_processes_info > "$PT_TMPDIR/notable_procs"
   like \
      "$(cat "$PT_TMPDIR/notable_procs")" \
      "${forked_pid}\\s+-17" \
      "notable_proccesses_info finds the process we manually changed earlier"

else
   skip 1 1 "oom_adj doesn't exist or isn't writeable"
fi

disown $forked_pid
kill -9 $forked_pid

# dmidecode_system_info

test_dmidecode_system_info () {
   local dir="$1"

   local CMD_DMIDECODE=""
   touch "$dir/outfile"
   dmidecode_system_info "$dir/outfile"

   cmd_ok '! test -s "$dir/outfile"' "If dmidecode isn't found, produces nothing"

   fake_command dmidecode '[$@]'
   dmidecode_system_info > "$dir/outfile"

   cat <<EOF >> "$dir/expected"
vendor    [-s system-manufacturer]
system    [-s system-manufacturer]; [-s system-product-name]; v[-s system-version] ([-s chassis-type])
servicetag    [-s system-serial-number]
EOF

   no_diff \
      "$dir/outfile" \
      "$dir/expected" \
      "..but if it's there, it gets called with the expected parameters "
}

mkdir "$PT_TMPDIR/dmidecode_system_info"
test_dmidecode_system_info "$PT_TMPDIR/dmidecode_system_info"

# fio_status_minus_a

for i in $( seq 1 4 ); do
   fake_command "fio-status" "\"; cat $samples/fio-status-00${i}.txt; echo \""
   fio_status_minus_a "$PT_TMPDIR/got"

   no_diff "$PT_TMPDIR/got" "$samples/Linux/004/fio-00$i" "fio_status_minus_a works for fio-status-00${i}.txt"
done
