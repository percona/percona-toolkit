# This program is copyright 2011-2012 Percona Inc.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.
# ###########################################################################
# collect_system_info package
# ###########################################################################

# Package: collect_system_info
# collects system information.

# XXX
# THIS LIB REQUIRES log_warn_die.sh, summary_common.sh, and alt_cmds.sh!
# XXX

set -u

# This is inside a function so it can take into account our PATH mungling.
setup_commands () {
   # While extremely unwieldly, this allows us to fake the commands when testing.
   CMD_SYSCTL="$(_which sysctl 2>/dev/null )"
   CMD_DMIDECODE="$(_which dmidecode 2>/dev/null )"
   CMD_ZONENAME="$(_which zonename 2>/dev/null )"
   CMD_DMESG="$(_which dmesg 2>/dev/null )"
   CMD_FILE="$(_which file 2>/dev/null )"
   CMD_LSPCI="$(_which lspci 2>/dev/null )"
   CMD_PRTDIAG="$(_which prtdiag 2>/dev/null )"
   CMD_SMBIOS="$(_which smbios 2>/dev/null )"
   CMD_GETENFORCE="$(_which getenforce 2>/dev/null )"
   CMD_PRTCONF="$(_which prtconf 2>/dev/null )"
   CMD_LVS="$(_which lvs 2>/dev/null)"
   CMD_VGS="$(_which vgs 2>/dev/null)"
   CMD_PRSTAT="$(_which prstat 2>/dev/null)"
   CMD_ISAINFO="$(_which isainfo 2>/dev/null)"
   CMD_TOP="$(_which top 2>/dev/null)"
   CMD_ARCCONF="$( _which arcconf 2>/dev/null )"
   CMD_HPACUCLI="$( _which hpacucli 2>/dev/null )"
   CMD_MEGACLI64="$( _which MegaCli64 2>/dev/null )"
   CMD_VMSTAT="$(_which vmstat 2>/dev/null)"
   CMD_IP="$( _which ip 2>/dev/null )"
   CMD_NETSTAT="$( _which netstat 2>/dev/null )"
   CMD_PSRINFO="$( _which psrinfo 2>/dev/null )"
   CMD_SWAPCTL="$( _which swapctl 2>/dev/null )"
   CMD_LSB_RELEASE="$( _which lsb_release 2>/dev/null )"
   CMD_ETHTOOL="$( _which ethtool 2>/dev/null )"
   CMD_GETCONF="$( _which getconf 2>/dev/null )"
   CMD_FIO_STATUS="$( _which fio-status 2>/dev/null )"
}

collect_system_data () { local PTFUNCNAME=collect_system_data;
   local data_dir="$1"

   if [ -r /var/log/dmesg -a -s /var/log/dmesg ]; then
      cat "/var/log/dmesg" > "$data_dir/dmesg_file"
   fi

   # ########################################################################
   # Grab a bunch of stuff and put it into temp files for later.
   # ########################################################################
   $CMD_SYSCTL -a > "$data_dir/sysctl" 2>/dev/null

   if [ "${CMD_LSPCI}" ]; then
      $CMD_LSPCI > "$data_dir/lspci_file" 2>/dev/null
   fi

   local platform="$(uname -s)"
   echo "platform    $platform"   >> "$data_dir/summary"
   echo "hostname    $(uname -n)" >> "$data_dir/summary"
   uptime >> "$data_dir/uptime"

   processor_info "$data_dir"
   find_release_and_kernel "$platform" >> "$data_dir/summary"
   cpu_and_os_arch "$platform"         >> "$data_dir/summary"
   find_virtualization "$platform" "$data_dir/dmesg_file" "$data_dir/lspci_file" >> "$data_dir/summary"
   dmidecode_system_info               >> "$data_dir/summary"

   if [ "${platform}" = "SunOS" -a "${CMD_ZONENAME}" ]; then
      echo "zonename    $($CMD_ZONENAME)" >> "$data_dir/summary"
   fi

   # Threading library
   if [ -x /lib/libc.so.6 ]; then
      echo "compiler    $(/lib/libc.so.6 | grep 'Compiled by' | cut -c13-)" >> "$data_dir/summary"
   fi

   local rss=$(ps -eo rss 2>/dev/null | awk '/[0-9]/{total += $1 * 1024} END {print total}')
   echo "rss    ${rss}" >> "$data_dir/summary"

   [ "$CMD_DMIDECODE" ] && $CMD_DMIDECODE > "$data_dir/dmidecode" 2>/dev/null

   find_memory_stats "$platform" > "$data_dir/memory"
   [ "$OPT_SUMMARIZE_MOUNTS" ] && mounted_fs_info "$platform" > "$data_dir/mounted_fs"
   raid_controller   "$data_dir/dmesg_file" "$data_dir/lspci_file" >> "$data_dir/summary"

   local controller="$(get_var raid_controller "$data_dir/summary")"
   propietary_raid_controller "$data_dir/raid-controller" "$data_dir/summary" "$data_dir" "$controller"

   [ "${platform}" = "Linux" ] && linux_exclusive_collection "$data_dir"

   if [ "$CMD_IP" -a "$OPT_SUMMARIZE_NETWORK" ]; then
      $CMD_IP -s link > "$data_dir/ip"
      network_device_info "$data_dir/ip" > "$data_dir/network_devices"
   fi

   [ "$CMD_SWAPCTL" ] && $CMD_SWAPCTL -s > "$data_dir/swapctl"

   if [ "$OPT_SUMMARIZE_PROCESSES" ]; then
      top_processes > "$data_dir/processes"
      notable_processes_info > "$data_dir/notable_procs"

      if [ "$CMD_VMSTAT" ]; then
         # Here we make an exception from our usual rule of not leaving
         # empty files, since the reporting code uses its existence
         # as an indicator to do the vmstat portion of the code,
         # and it's entirely possible to have reached that spot without
         # having the forked process output anything.
         touch "$data_dir/vmstat"
         (
            $CMD_VMSTAT 1 $OPT_SLEEP > "$data_dir/vmstat"
         ) &
      fi
   fi

   # Fusion-io cards
   fio_status_minus_a "$data_dir/fusion-io_card"
   
   # Clean the data directory, don't leave empty files
   for file in $data_dir/*; do
      # The vmstat file gets special treatmeant, see above.
      [ "$file" = "vmstat" ] && continue
      [ ! -s "$file" ] && rm "$file"
   done
}

fio_status_minus_a () {
   local file="$1"
   local full_output="${file}_original_output"
   [ -z "$CMD_FIO_STATUS" ] && return;
   $CMD_FIO_STATUS -a > "$full_output"

   cat <<'EOP' > "$PT_TMPDIR/fio_status_format.pl"
   my $tmp_adapter;
   while (<>) {
      if ( /Fusion-io driver version:\s*(.+)/ ) {
         print "driver_version    $1"
      }
      next unless /^Adapter:(.+)/;
      $tmp_adapter = $1;
      last;
   }

   $/ = "\nAdapter: ";
   $_ = $tmp_adapter . "\n" . scalar(<>);
   my @adapters;
   do {
      my ($adapter, $adapter_general) = /\s*(.+)\s*\n\s*(.+)/m;
      $adapter =~ tr/ /:/;
      $adapter .= "::" . scalar(@adapters); # To differentiate two adapters with the same name
      push @adapters, $adapter;
      my ($connected_modules) = /Connected \S+ modules?:\s*\n(.+?\n)\n/smg;
      my @connected_modules   = $connected_modules =~ /\s+([^:]+):.+\n/g;

      print "${adapter}_general     $adapter_general";
      print "${adapter}_modules     @connected_modules";
      
      for my $module (@connected_modules) {
         my ($rest, $attached, $general, $firmware, $temperature, $media_status) = /(
            ^ \s* $module  \s+ (Attached[^\n]+) \n
              \s+ ([^\n]+)                      \n # All the second line
              .+? (Firmware\s+[^\n]+)           \n
              .+? (Internal \s+ temperature:[^\n]+) \n
              .+? ((?:Media | Reserve \s+ space) \s+ status:[^\n]+) \n
              .+?(?:\n\n|\z)
         )/xsm;
         my ($pbw) = $rest =~ /.+?(Rated \s+ PBW:[^\n]+)/xsm;
         print "${adapter}_${module}_attached_as      $attached";
         print "${adapter}_${module}_general          $general";
         print "${adapter}_${module}_firmware         $firmware";
         print "${adapter}_${module}_media_status     $media_status";
         print "${adapter}_${module}_temperature      $temperature";
         print "${adapter}_${module}_rated_pbw        $pbw" if $pbw;
      }
   } while <>;

   print "adapters     @adapters\n";
   
   exit;
EOP

   perl -wln "$PT_TMPDIR/fio_status_format.pl" "$full_output" > "$file"
}

linux_exclusive_collection () { local PTFUNCNAME=linux_exclusive_collection;
   local data_dir="$1"

   echo "threading    $(getconf GNU_LIBPTHREAD_VERSION)" >> "$data_dir/summary"

   local getenforce=""
   [ "$CMD_GETENFORCE" ] && getenforce="$($CMD_GETENFORCE 2>&1)"
   echo "getenforce    ${getenforce:-"No SELinux detected"}" >> "$data_dir/summary"

   if [ -e "$data_dir/sysctl" ]; then
      echo "swappiness    $(awk '/vm.swappiness/{print $3}' "$data_dir/sysctl")" >> "$data_dir/summary"

      local dirty_ratio="$(awk '/vm.dirty_ratio/{print $3}' "$data_dir/sysctl")"
      local dirty_bg_ratio="$(awk '/vm.dirty_background_ratio/{print $3}' "$data_dir/sysctl")"
      if [ "$dirty_ratio" -a "$dirty_bg_ratio" ]; then
         echo "dirtypolicy    $dirty_ratio, $dirty_bg_ratio" >> "$data_dir/summary"
      fi

      local dirty_bytes="$(awk '/vm.dirty_bytes/{print $3}' "$data_dir/sysctl")"
      if [ "$dirty_bytes" ]; then
         echo "dirtystatus     $(awk '/vm.dirty_bytes/{print $3}' "$data_dir/sysctl"), $(awk '/vm.dirty_background_bytes/{print $3}' "$data_dir/sysctl")" >> "$data_dir/summary"
      fi
   fi

   schedulers_and_queue_size "$data_dir/summary" > "$data_dir/partitioning"

   for file in dentry-state file-nr inode-nr; do
      echo "${file}    $(cat /proc/sys/fs/${file} 2>&1)" >> "$data_dir/summary"
   done

   [ "$CMD_LVS" -a -x "$CMD_LVS" ] && $CMD_LVS 1>"$data_dir/lvs" 2>"$data_dir/lvs.stderr"

   [ "$CMD_VGS" -a -x "$CMD_VGS" ] && \
      $CMD_VGS -o vg_name,vg_size,vg_free 2>/dev/null > "$data_dir/vgs"

   [ "$CMD_NETSTAT" -a "$OPT_SUMMARIZE_NETWORK" ] && \
      $CMD_NETSTAT -antp > "$data_dir/netstat" 2>/dev/null
}

network_device_info () {
   local ip_minus_s_file="$1"

   if [ "$CMD_ETHTOOL" ]; then
      local tempfile="$PT_TMPDIR/ethtool_output_temp"
      # For each entry in the ip -s link dump, check if itu starts with a number.
      # If it does, print the second field. Then remove the colon and everything
      # following that. Then skip what are usually interfaces.
      for device in $( awk '/^[1-9]/{ print $2 }'  "$ip_minus_s_file" \
                        | awk -F: '{print $1}'     \
                        | grep -v '^lo\|^in\|^gr'  \
                        | sort -u ); do
         # Call ethtool on what might be a device
         ethtool $device > "$tempfile" 2>/dev/null

         # If there isn't any information, we are most likely not dealing with
         # a device at all, but an interface, so skip it, otherwise print
         # ethtool's output.
         if ! grep -q 'No data available' "$tempfile"; then
            cat "$tempfile"
         fi
      done
   fi
}

# Try to find all sorts of different files that say what the release is.
find_release_and_kernel () { local PTFUNCNAME=find_release_and_kernel;
   local platform="$1"

   local kernel=""
   local release=""
   if [ "${platform}" = "Linux" ]; then
      kernel="$(uname -r)"
      if [ -e /etc/fedora-release ]; then
         release=$(cat /etc/fedora-release);
      elif [ -e /etc/redhat-release ]; then
         release=$(cat /etc/redhat-release);
      elif [ -e /etc/system-release ]; then
         release=$(cat /etc/system-release);
      elif [ "$CMD_LSB_RELEASE" ]; then
         release="$($CMD_LSB_RELEASE -ds) ($($CMD_LSB_RELEASE -cs))"
      elif [ -e /etc/lsb-release ]; then
         release=$(grep DISTRIB_DESCRIPTION /etc/lsb-release |awk -F'=' '{print $2}' |sed 's#"##g');
      elif [ -e /etc/debian_version ]; then
         release="Debian-based version $(cat /etc/debian_version)";
         if [ -e /etc/apt/sources.list ]; then
             local code=` awk  '/^deb/ {print $3}' /etc/apt/sources.list       \
                        | awk -F/ '{print $1}'| awk 'BEGIN {FS="|"}{print $1}' \
                        | sort | uniq -c | sort -rn | head -n1 | awk '{print $2}'`
             release="${release} (${code})"
      fi
      elif ls /etc/*release >/dev/null 2>&1; then
         if grep -q DISTRIB_DESCRIPTION /etc/*release; then
            release=$(grep DISTRIB_DESCRIPTION /etc/*release | head -n1);
         else
            release=$(cat /etc/*release | head -n1);
         fi
      fi
   elif     [ "${platform}" = "FreeBSD" ] \
         || [ "${platform}" = "NetBSD"  ] \
         || [ "${platform}" = "OpenBSD" ]; then
      release="$(uname -r)"
      kernel="$($CMD_SYSCTL -n "kern.osrevision")"
   elif [ "${platform}" = "SunOS" ]; then
      release="$(head -n1 /etc/release)"
      if [ -z "${release}" ]; then
         release="$(uname -r)"
      fi
      kernel="$(uname -v)"
   fi
   echo "kernel    $kernel"
   echo "release    $release"
}

cpu_and_os_arch () { local PTFUNCNAME=cpu_and_os_arch;
   local platform="$1"

   local CPU_ARCH='32-bit'
   local OS_ARCH='32-bit'
   if [ "${platform}" = "Linux" ]; then
      if grep -q ' lm ' /proc/cpuinfo; then
         CPU_ARCH='64-bit'
      fi
   elif [ "${platform}" = "FreeBSD" ] || [ "${platform}" = "NetBSD" ]; then
      if $CMD_SYSCTL "hw.machine_arch" | grep -v 'i[36]86' >/dev/null; then
         CPU_ARCH='64-bit'
      fi
   elif [ "${platform}" = "OpenBSD" ]; then
      if $CMD_SYSCTL "hw.machine" | grep -v 'i[36]86' >/dev/null; then
         CPU_ARCH='64-bit'
      fi
   elif [ "${platform}" = "SunOS" ]; then
      if $CMD_ISAINFO -b | grep 64 >/dev/null ; then
         CPU_ARCH="64-bit"
      fi
   fi
   if [ -z "$CMD_FILE" ]; then
      if [ "$CMD_GETCONF" ] && $CMD_GETCONF LONG_BIT 1>/dev/null 2>&1; then
         OS_ARCH="$($CMD_GETCONF LONG_BIT 2>/dev/null)-bit"
      else
         OS_ARCH='N/A'
      fi
   elif $CMD_FILE /bin/sh | grep '64-bit' >/dev/null; then
       OS_ARCH='64-bit'
   fi

   echo "CPU_ARCH    $CPU_ARCH"
   echo "OS_ARCH    $OS_ARCH"
}

# We look in dmesg for virtualization information first, because it's often
# available to non-root users and usually has telltale signs.  It's most
# reliable to look at /var/log/dmesg if possible.  There are a number of
# other ways to find out if a system is virtualized.
find_virtualization () { local PTFUNCNAME=find_virtualization;
   local platform="$1"
   local dmesg_file="$2"
   local lspci_file="$3"

   local tempfile="$PT_TMPDIR/find_virtualziation.tmp"

   local virt=""
   if [ -s "$dmesg_file" ]; then
      virt="$(find_virtualization_dmesg "$dmesg_file")"
   fi
   if [ -z "${virt}" ] && [ -s "$lspci_file" ]; then
      if grep -qi "virtualbox" "$lspci_file" ; then
         virt="VirtualBox"
      elif grep -qi "vmware" "$lspci_file" ; then
         virt="VMWare"
      fi
   elif [ "${platform}" = "FreeBSD" ]; then
      if ps -o stat | grep J ; then
         virt="FreeBSD Jail"
      fi
   elif [ "${platform}" = "SunOS" ]; then
      if [ "$CMD_PRTDIAG" ] && $CMD_PRTDIAG > "$tempfile" 2>/dev/null; then
         virt="$(find_virtualization_generic "$tempfile" )"
      elif [ "$CMD_SMBIOS" ] && $CMD_SMBIOS > "$tempfile" 2>/dev/null; then
         virt="$(find_virtualization_generic "$tempfile" )"
      fi
   elif [ -e /proc/user_beancounters ]; then
      virt="OpenVZ/Virtuozzo"
   fi
   echo "virt    ${virt:-"No virtualization detected"}"
}

# ##############################################################################
# Try to figure out if a system is a guest by looking at prtdiag, smbios, etc.
# ##############################################################################
find_virtualization_generic() { local PTFUNCNAME=find_virtualization_generic;
   local file="$1"
   if grep -i -e "virtualbox" "$file" >/dev/null; then
      echo "VirtualBox"
   elif grep -i -e "vmware" "$file" >/dev/null; then
      echo "VMWare"
   fi
}

 # ##############################################################################
# Parse the output of dmesg and detect virtualization.
# ##############################################################################
find_virtualization_dmesg () { local PTFUNCNAME=find_virtualization_dmesg;
   local file="$1"
   if grep -qi -e "vmware" -e "vmxnet" -e 'paravirtualized kernel on vmi' "${file}"; then
      echo "VMWare";
   elif grep -qi -e 'paravirtualized kernel on xen' -e 'Xen virtual console' "${file}"; then
      echo "Xen";
   elif grep -qi "qemu" "${file}"; then
      echo "QEmu";
   elif grep -qi 'paravirtualized kernel on KVM' "${file}"; then
      echo "KVM";
   elif grep -q "VBOX" "${file}"; then
      echo "VirtualBox";
   elif grep -qi 'hd.: Virtual .., ATA.*drive' "${file}"; then
      echo "Microsoft VirtualPC";
   fi
}

# TODO: Maybe worth it to just dump dmidecode once and parse that?
dmidecode_system_info () { local PTFUNCNAME=dmidecode_system_info;
   if [ "${CMD_DMIDECODE}" ]; then
      local vendor="$($CMD_DMIDECODE -s "system-manufacturer" 2>/dev/null | sed 's/ *$//g')"
      echo "vendor    ${vendor}"
      if [ "${vendor}" ]; then
         local product="$($CMD_DMIDECODE -s "system-product-name" 2>/dev/null | sed 's/ *$//g')"
         local version="$($CMD_DMIDECODE -s "system-version" 2>/dev/null | sed 's/ *$//g')"
         local chassis="$($CMD_DMIDECODE -s "chassis-type" 2>/dev/null | sed 's/ *$//g')"
         local servicetag="$($CMD_DMIDECODE -s "system-serial-number" 2>/dev/null | sed 's/ *$//g')"
         local system="${vendor}; ${product}; v${version} (${chassis})"

         echo "system    ${system}"
         echo "servicetag    ${servicetag:-"Not found"}"
      fi
   fi
}

find_memory_stats () { local PTFUNCNAME=find_memory_stats;
   local platform="$1"

   if [ "${platform}" = "Linux" ]; then
      free -b
      cat /proc/meminfo
   elif [ "${platform}" = "SunOS" ]; then
      $CMD_PRTCONF | awk -F: '/Memory/{print $2}'
   fi
}

mounted_fs_info () { local PTFUNCNAME=mounted_fs_info;
   local platform="$1"

   if [ "${platform}" != "SunOS" ]; then
      local cmd="df -h"
      if [ "${platform}" = "Linux" ]; then
         cmd="df -h -P"
      fi
      $cmd  | sort > "$PT_TMPDIR/mounted_fs_info.tmp"
      mount | sort | join "$PT_TMPDIR/mounted_fs_info.tmp" -
   fi
}

# ########################################################################
# We look in lspci first because it's more reliable, then dmesg, because it's
# often available to non-root users.  It's most reliable to look at
# /var/log/dmesg if possible.
# ########################################################################
raid_controller () { local PTFUNCNAME=raid_controller;
   local dmesg_file="$1"
   local lspci_file="$2"

   local tempfile="$PT_TMPDIR/raid_controller.tmp"

   local controller=""
   if [ -s "$lspci_file" ]; then
      controller="$(find_raid_controller_lspci "$lspci_file")"
   fi
   if [ -z "${controller}" ] && [ -s "$dmesg_file" ]; then
      controller="$(find_raid_controller_dmesg "$dmesg_file")"
   fi

   echo "raid_controller    ${controller:-"No RAID controller detected"}"
}

# ##############################################################################
# Parse the output of dmesg and detect RAID controllers.
# ##############################################################################
find_raid_controller_dmesg () { local PTFUNCNAME=find_raid_controller_dmesg;
   local file="$1"
   local pat='scsi[0-9].*: .*'
   if grep -qi "${pat}megaraid" "${file}"; then
      echo 'LSI Logic MegaRAID SAS'
   elif grep -q "Fusion MPT SAS" "${file}"; then
      echo 'Fusion-MPT SAS'
   elif grep -q "${pat}aacraid" "${file}"; then
      echo 'AACRAID'
   elif grep -q "${pat}3ware [0-9]* Storage Controller" "${file}"; then
      echo '3Ware'
   fi
}

# ##############################################################################
# Parse the output of lspci and detect RAID controllers.
# ##############################################################################
find_raid_controller_lspci () { local PTFUNCNAME=find_raid_controller_lspci;
   local file="$1"
   if grep -q "RAID bus controller: LSI Logic / Symbios Logic MegaRAID SAS" "${file}" \
     || grep -q "RAID bus controller: LSI Logic / Symbios Logic LSI MegaSAS" $file; then
      echo 'LSI Logic MegaRAID SAS'
   elif grep -q "Fusion-MPT SAS" "${file}"; then
      echo 'Fusion-MPT SAS'
   elif grep -q "RAID bus controller: LSI Logic / Symbios Logic Unknown" "${file}"; then
      echo 'LSI Logic Unknown'
   elif grep -q "RAID bus controller: Adaptec AAC-RAID" "${file}"; then
      echo 'AACRAID'
   elif grep -q "3ware [0-9]* Storage Controller" "${file}"; then
      echo '3Ware'
   elif grep -q "Hewlett-Packard Company Smart Array" "${file}"; then
      echo 'HP Smart Array'
   elif grep -q " RAID bus controller: " "${file}"; then
      awk -F: '/RAID bus controller\:/ {print $3" "$5" "$6}' "${file}"
   fi
}

schedulers_and_queue_size () { local PTFUNCNAME=schedulers_and_queue_size;
   local file="$1"

   local disks="$(ls /sys/block/ | grep -v -e ram -e loop -e 'fd[0-9]' | xargs echo)"
   echo "internal::disks    $disks" >> "$file"

   for disk in $disks; do
      if [ -e "/sys/block/${disk}/queue/scheduler" ]; then
         echo "internal::${disk}    $(cat /sys/block/${disk}/queue/scheduler | grep -o '\[.*\]') $(cat /sys/block/${disk}/queue/nr_requests)" >> "$file"
         fdisk -l "/dev/${disk}" 2>/dev/null
      fi
   done
}

top_processes () { local PTFUNCNAME=top_processes;
   if [ "$CMD_PRSTAT" ]; then
      $CMD_PRSTAT | head
   elif [ "$CMD_TOP" ]; then
      local cmd="$CMD_TOP -bn 1"
      if    [ "${platform}" = "FreeBSD" ] \
         || [ "${platform}" = "NetBSD"  ] \
         || [ "${platform}" = "OpenBSD" ]; then
         cmd="$CMD_TOP -b -d 1"
      fi
      $cmd \
         | sed -e 's# *$##g' -e '/./{H;$!d;}' -e 'x;/PID/!d;' \
         | grep . \
         | head
   fi
}

notable_processes_info () { local PTFUNCNAME=notable_processes_info;
   local format="%5s    %+2d    %s\n"
   local sshd_pid=$(ps -eo pid,args | awk '$2 ~ /\/usr\/sbin\/sshd/ { print $1; exit }')

   echo "  PID    OOM    COMMAND"

   # First, let's find the oom value of sshd
   if [ "$sshd_pid" ]; then
      printf "$format" "$sshd_pid" "$(get_oom_of_pid $sshd_pid)" "sshd"
   else
      printf "%5s    %3s    %s\n" "?" "?" "sshd doesn't appear to be running"
   fi

   # Disabling PTDEBUG for the remainder of this function, otherwise we get several
   # hundred lines of mostly useless debug output
   local PTDEBUG=""
   # Let's find out if any process has an oom of -17
   ps -eo pid,ucomm | grep '^[0-9]' | while read pid proc; do
      # Skip sshd, since we manually checked this before
      [ "$sshd_pid" ] && [ "$sshd_pid" = "$pid" ] && continue
      local oom="$(get_oom_of_pid $pid)"
      if [ "$oom" ] && [ "$oom" != "?" ] && [ "$oom" = "-17" ]; then
         printf "$format" "$pid" "$oom" "$proc"
      fi
   done
}

processor_info () { local PTFUNCNAME=processor_info;
   local data_dir="$1"
   if [ -f /proc/cpuinfo ]; then
      cat /proc/cpuinfo > "$data_dir/proc_cpuinfo_copy" 2>/dev/null
   elif [ "${platform}" = "SunOS" ]; then
      $CMD_PSRINFO -v > "$data_dir/psrinfo_minus_v"
   fi 
}

# ########################################################################
# Attempt to get, parse, and print RAID controller status from possibly
# proprietary management software.  Any executables that are normally stored
# in a weird location, such as /usr/StorMan/arcconf, should have their
# location added to $PATH at the beginning of main().
# ########################################################################
propietary_raid_controller () { local PTFUNCNAME=propietary_raid_controller;
   local file="$1"
   local variable_file="$2"
   local data_dir="$3"
   local controller="$4"

   notfound=""
   if [ "${controller}" = "AACRAID" ]; then
      if [ -z "$CMD_ARCCONF" ]; then
         notfound="e.g. http://www.adaptec.com/en-US/support/raid/scsi_raid/ASR-2120S/"
      elif $CMD_ARCCONF getconfig 1 > "$file" 2>/dev/null; then
         echo "internal::raid_opt    1" >> "$variable_file"
      fi
   elif [ "${controller}" = "HP Smart Array" ]; then
      if [ -z "$CMD_HPACUCLI" ]; then
         notfound="your package repository or the manufacturer's website"
      elif $CMD_HPACUCLI ctrl all show config > "$file" 2>/dev/null; then
         echo "internal::raid_opt    2" >> "$variable_file"
      fi
   elif [ "${controller}" = "LSI Logic MegaRAID SAS" ]; then
      if [ -z "$CMD_MEGACLI64" ]; then 
         notfound="your package repository or the manufacturer's website"
      else
         echo "internal::raid_opt    3" >> "$variable_file"
         $CMD_MEGACLI64 -AdpAllInfo -aALL -NoLog > "$data_dir/lsi_megaraid_adapter_info.tmp" 2>/dev/null
         $CMD_MEGACLI64 -AdpBbuCmd -GetBbuStatus -aALL -NoLog > "$data_dir/lsi_megaraid_bbu_status.tmp" 2>/dev/null
         $CMD_MEGACLI64 -LdPdInfo -aALL -NoLog > "$data_dir/lsi_megaraid_devices.tmp" 2>/dev/null
      fi
   fi

   if [ "${notfound}" ]; then
      echo "internal::raid_opt    0" >> "$variable_file"
      echo "   RAID controller software not found; try getting it from" > "$file"
      echo "   ${notfound}" >> "$file"
   fi
}

# ###########################################################################
# End collect_system_info package
# ###########################################################################
