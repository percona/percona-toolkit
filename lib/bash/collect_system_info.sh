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

PT_SUMMARY_SKIP="${PT_SUMMARY_SKIP:-""}"

set -u

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

collect_system_data () { local FUNCNAME=collect_system_data;
   local data_dir="$1"

   if [ -r /var/log/dmesg -a -s /var/log/dmesg ]; then
      cat "/var/log/dmesg" > "$data_dir/dmesg_file"
   fi

   # ########################################################################
   # Grab a bunch of stuff and put it into temp files for later.
   # ########################################################################
   $CMD_SYSCTL -a > "$data_dir/sysctl" 2>/dev/null

   if [ -n "${CMD_LSPCI}" ]; then
      $CMD_LSPCI > "$data_dir/lspci_file" 2>/dev/null
   fi

   local platform="$(uname -s)"
   echo "platform    $platform" >> "$data_dir/summary"
   echo "hostname    $(uname -n)" >> "$data_dir/summary"
   echo "uptime    $(uptime | awk '{print substr($0, index($0, "up") + 3)}')" >> "$data_dir/summary"

   processor_info "$data_dir"
   find_release_and_kernel "$data_dir/summary" "$platform"
   cpu_and_os_arch   "$data_dir/summary" "$platform"
   find_virtualization "$data_dir/summary" "$platform" "$data_dir/dmesg_file" "$data_dir/lspci_file"
   dmidecode_system_info "$data_dir/summary"

   if [ "${platform}" = "SunOS" ] && [ -n "${CMD_ZONENAME}" ]; then
      echo "zonename    $($CMD_ZONENAME)" >> "$data_dir/summary"
   fi

   # Threading library
   if [ "${platform}" = "Linux" ]; then
      echo "threading    $(getconf GNU_LIBPTHREAD_VERSION)" >> "$data_dir/summary"
   fi
   if [ -x /lib/libc.so.6 ]; then
      echo "compiler    $(/lib/libc.so.6 | grep 'Compiled by' | cut -c13-)" >> "$data_dir/summary"
   fi

   if [ "${platform}" = "Linux" ]; then
      local getenforce=""
      if [ -n "$CMD_GETENFORCE" ]; then
         getenforce="$($CMD_GETENFORCE 2>&1)";
      fi
      echo "getenforce    ${getenforce:-No SELinux detected}" >> "$data_dir/summary"
   fi

   local rss=$(ps -eo rss 2>/dev/null | awk '/[0-9]/{total += $1 * 1024} END {print total}')
   echo "rss    ${rss}" >> "$data_dir/summary"

   if [ "${platform}" = "Linux" ]; then
      echo "swappiness    $(awk '/vm.swappiness/{print $3}' "$data_dir/sysctl")">> "$data_dir/summary"
      echo "dirtypolicy    $(awk '/vm.dirty_ratio/{print $3}' "$data_dir/sysctl"), $(awk '/vm.dirty_background_ratio/{print $3}' "$data_dir/sysctl")" >> "$data_dir/summary"
      if $(awk '/vm.dirty_bytes/{print $3}' "$data_dir/sysctl") > /dev/null 2>&1; then
         echo "dirtystatus     $(awk '/vm.dirty_bytes/{print $3}' "$data_dir/sysctl"), $(awk '/vm.dirty_background_bytes/{print $3}' "$data_dir/sysctl")" >> "$data_dir/summary"
      fi
   fi

   if [ -n "$CMD_DMIDECODE" ]; then
      $CMD_DMIDECODE > "$data_dir/dmidecode" 2>/dev/null
   fi

   find_memory_stats "$data_dir/memory" "$platform"
   mounted_fs_info   "$data_dir/mounted_fs" "$platform" "$PT_SUMMARY_SKIP"
   raid_controller   "$data_dir/summary" "$data_dir/dmesg_file" "$data_dir/lspci_file"

   local controller="$(get_var raid_controller "$data_dir/summary")"
   propietary_raid_controller "$data_dir/raid-controller" "$data_dir/summary" "$data_dir" "$controller"

   if [ "${platform}" = "Linux" ]; then
      linux_exclusive_collection "$data_dir"
   fi

   if [ -n "$CMD_IP" ] && echo "${PT_SUMMARY_SKIP}" | grep -v NETWORK >/dev/null; then
      $CMD_IP -s link > "$data_dir/ip"
   fi

   if [ -n "$CMD_SWAPCTL" ]; then
      $CMD_SWAPCTL -s > "$data_dir/swapctl"
   fi

   top_processes "$data_dir/processes" "$PT_SUMMARY_SKIP"
   notable_processes_info "$data_dir/notable_procs" "$PT_SUMMARY_SKIP"

   if [ -n "$CMD_VMSTAT" ]; then
      touch "$data_dir/vmstat"
      (
         $CMD_VMSTAT 1 $OPT_SLEEP > "$data_dir/vmstat"
      ) &
   fi
}

linux_exclusive_collection () { local FUNCNAME=linux_exclusive_collection;
   local data_dir="$1"

   schedulers_and_queue_size "$data_dir/summary" "$data_dir/partitioning"

   for file in dentry-state file-nr inode-nr; do
      echo "${file}    $(cat /proc/sys/fs/${file} 2>&1)" >> "$data_dir/summary"
   done

   if [ -n "$CMD_LVS" ] && test -x "$CMD_LVS"; then
      $CMD_LVS 1>"$data_dir/lvs" 2>&1
   fi

   if [ -n "$CMD_VGS" ] && test -x "$CMD_VGS"; then
      $CMD_VGS -o vg_name,vg_size,vg_free 2>/dev/null > "$data_dir/vgs"
   fi

   if [ -n "$CMD_NETSTAT" ] && echo "${PT_SUMMARY_SKIP}" | grep -v NETWORK >/dev/null; then
      $CMD_NETSTAT -antp > "$data_dir/netstat" 2>/dev/null
   fi
}

# Try to find all sorts of different files that say what the release is.
find_release_and_kernel () { local FUNCNAME=find_release_and_kernel;
   local file="$1"
   local platform="$2"

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
      elif _which lsb_release >/dev/null 2>&1; then
         release="$(lsb_release -ds) ($(lsb_release -cs))"
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
   elif [ "${platform}" = "FreeBSD" ]    \
         || [ "${platform}" = "NetBSD" ] \
         || [ "${platform}" = "OpenBSD" ]; then
      release="$(uname -r)"
      kernel="$($CMD_SYSCTL -n kern.osrevision)"
   elif [ "${platform}" = "SunOS" ]; then
      release="$(head -n1 /etc/release)"
      if [ -z "${release}" ]; then
         release="$(uname -r)"
      fi
      kernel="$(uname -v)"
   fi
   echo "kernel    $kernel" >> "$file"
   echo "release    $release" >> "$file"
}

cpu_and_os_arch () { local FUNCNAME=cpu_and_os_arch;
   local file="$1"
   local platform="$2"

   local CPU_ARCH='32-bit'
   local OS_ARCH='32-bit'
   if [ "${platform}" = "Linux" ]; then
      if [ "$(grep -q ' lm ' /proc/cpuinfo)" ]; then
         CPU_ARCH='64-bit'
      fi
   elif [ "${platform}" = "FreeBSD" ] || [ "${platform}" = "NetBSD" ]; then
      if $CMD_SYSCTL hw.machine_arch | grep -v 'i[36]86' >/dev/null; then
         CPU_ARCH='64-bit'
      fi
   elif [ "${platform}" = "OpenBSD" ]; then
      if $CMD_SYSCTL hw.machine | grep -v 'i[36]86' >/dev/null; then
         CPU_ARCH='64-bit'
      fi
   elif [ "${platform}" = "SunOS" ]; then
      if $CMD_ISAINFO -b | grep 64 >/dev/null ; then
         CPU_ARCH="64-bit"
      fi
   fi
   if [ -z "$CMD_FILE" ]; then
      OS_ARCH='N/A'
   elif $CMD_FILE /bin/sh | grep '64-bit' >/dev/null; then
       OS_ARCH='64-bit'
   fi

   echo "CPU_ARCH    $CPU_ARCH" >> "$file"
   echo "OS_ARCH    $OS_ARCH" >> "$file"
}

# We look in dmesg for virtualization information first, because it's often
# available to non-root users and usually has telltale signs.  It's most
# reliable to look at /var/log/dmesg if possible.  There are a number of
# other ways to find out if a system is virtualized.
find_virtualization () { local FUNCNAME=find_virtualization;
   local vars_file="$1"
   local platform="$2"
   local dmesg_file="$3"
   local lspci_file="$4"

   local tempfile="$TMPDIR/find_virtualziation.tmp"

   local virt=""
   if [ -s "$dmesg_file" ]; then
      virt="$(find_virtualization_dmesg "$dmesg_file")"
   fi
   if [ -z "${virt}" ] && [ -s "$lspci_file" ]; then
      if grep -qi virtualbox "$lspci_file" ; then
         virt=VirtualBox
      elif grep -qi vmware "$lspci_file" ; then
         virt=VMWare
      fi
   elif [ "${platform}" = "FreeBSD" ]; then
      if ps -o stat | grep J ; then
         virt="FreeBSD Jail"
      fi
   elif [ "${platform}" = "SunOS" ]; then
      if [ -n "$CMD_PRTDIAG" ] && $CMD_PRTDIAG > "$tempfile" 2>/dev/null; then
         virt="$(find_virtualization_generic "$tempfile" )"
      elif [ -n "$CMD_SMBIOS" ] && $CMD_SMBIOS > "$tempfile" 2>/dev/null; then
         virt="$(find_virtualization_generic "$tempfile" )"
      fi
   elif [ -e /proc/user_beancounters ]; then
      virt="OpenVZ/Virtuozzo"
   fi
   echo "virt    ${virt:-"No virtualization detected"}" >> "$vars_file"
}

# ##############################################################################
# Try to figure out if a system is a guest by looking at prtdiag, smbios, etc.
# ##############################################################################
find_virtualization_generic() { local PTFUNCNAME=find_virtualization_generic;
   local file="$1"
   if grep -i -e virtualbox "$file" >/dev/null; then
      echo VirtualBox
   elif grep -i -e vmware "$file" >/dev/null; then
      echo VMWare
   fi
}

 # ##############################################################################
# Parse the output of dmesg and detect virtualization.
# ##############################################################################
find_virtualization_dmesg () { local PTFUNCNAME=find_virtualization_dmesg;
   local file="$1"
   if grep -qi -e vmware -e vmxnet -e 'paravirtualized kernel on vmi' "${file}"; then
      echo "VMWare";
   elif grep -qi -e 'paravirtualized kernel on xen' -e 'Xen virtual console' "${file}"; then
      echo "Xen";
   elif grep -qi qemu "${file}"; then
      echo "QEmu";
   elif grep -qi 'paravirtualized kernel on KVM' "${file}"; then
      echo "KVM";
   elif grep -q VBOX "${file}"; then
      echo "VirtualBox";
   elif grep -qi 'hd.: Virtual .., ATA.*drive' "${file}"; then
      echo "Microsoft VirtualPC";
   fi
}

# TODO: Maybe worth it to just dump dmidecode once and parse that?
dmidecode_system_info () { local FUNCNAME=dmidecode_system_info;
   local file="$1"
   if [ -n "${CMD_DMIDECODE}" ]; then
      local vendor="$($CMD_DMIDECODE -s system-manufacturer 2>/dev/null | sed 's/ *$//g')"
      echo "vendor    ${vendor}" >> "$file"
      if [ "${vendor}" ]; then
         local product="$($CMD_DMIDECODE -s system-product-name 2>/dev/null | sed 's/ *$//g')"
         local version="$($CMD_DMIDECODE -s system-version 2>/dev/null | sed 's/ *$//g')"
         local chassis="$($CMD_DMIDECODE -s chassis-type 2>/dev/null | sed 's/ *$//g')"
         local servicetag="$($CMD_DMIDECODE -s system-serial-number 2>/dev/null | sed 's/ *$//g')"
         local system="${vendor}; ${product}; v${version} (${chassis})"

         echo "system    ${system}" >> "$file"
         echo "servicetag    ${servicetag:-Not found}" >> "$file"
      fi
   fi
}

find_memory_stats () { local PTFUNCNAME=find_memory_stats;
   local file="$1"
   local platform="$2"
   if [ "${platform}" = "Linux" ]; then
      _d "In Linux, so saving the output of free -b" \
         "and /proc/meminfo into $file"
      free -b > "$file"
      cat /proc/meminfo >> "$file"
   elif [ "${platform}" = "SunOS" ]; then
      _d "In SunOS, calling prtconf"
      $CMD_PRTCONF | awk -F: '/Memory/{print $2}' > "$file"
   fi
}

mounted_fs_info () { local PTFUNCNAME=mounted_fs_info;
   local file="$1"
   local platform="$2"
   local skip="${3:-$PT_SUMMARY_SKIP}"

   if echo "${skip}" | grep -v MOUNT >/dev/null; then
      if [ "${platform}" != "SunOS" ]; then
         local cmd="df -h"
         if [ "${platform}" = "Linux" ]; then
            cmd="df -h -P"
         fi
         _d "calling $cmd"
         $cmd  | sort > "$TMPDIR/mounted_fs_info.tmp"
         mount | sort | join "$TMPDIR/mounted_fs_info.tmp" - > "$file"
      fi
   fi
}

# ########################################################################
# We look in lspci first because it's more reliable, then dmesg, because it's
# often available to non-root users.  It's most reliable to look at
# /var/log/dmesg if possible.
# ########################################################################
raid_controller () { local PTFUNCNAME=raid_controller;
   local file="$1"
   local dmesg_file="$2"
   local lspci_file="$3"

   local tempfile="$TMPDIR/raid_controller.tmp"

   local controller=""
   if [ -s "$lspci_file" ]; then
      controller="$(find_raid_controller_lspci "$lspci_file")"
   fi
   if [ -z "${controller}" ] && [ -s "$dmesg_file" ]; then
      controller="$(find_raid_controller_dmesg "$dmesg_file")"
   fi

   echo "raid_controller    ${controller:-"No RAID controller detected"}" >> "$file"
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
   if grep -q "RAID bus controller: LSI Logic / Symbios Logic MegaRAID SAS" "${file}"; then
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

schedulers_and_queue_size () { local FUNCNAME=schedulers_and_queue_size;
   local file="$1"
   local disk_partitioning_file="$2"

   local disks="$(ls /sys/block/ | grep -v -e ram -e loop -e 'fd[0-9]')"
   echo "disks    $disks" >> "$file"
   echo "" > "$disk_partitioning_file"
   for disk in $disks; do
      if [ -e "/sys/block/${disk}/queue/scheduler" ]; then
         echo "internal::${disk}    $(cat /sys/block/${disk}/queue/scheduler | grep -o '\[.*\]') $(cat /sys/block/${disk}/queue/nr_requests)" >> "$file"
         fdisk -l "/dev/${disk}" >> "$disk_partitioning_file" 2>/dev/null
      fi
   done
}

top_processes () { local FUNCNAME=top_processes;
   local top_processes_file="$1"
   local skip="${2:-"$PT_SUMMARY_SKIP"}"

   if echo "${skip}" | grep -v PROCESS >/dev/null; then
      if [ -n "$CMD_PRSTAT" ]; then
         $CMD_PRSTAT | head > "$top_processes_file"
      elif [ -n "$CMD_TOP" ]; then
         local cmd="$CMD_TOP -bn 1"
         if [ "${platform}" = "FreeBSD" ] \
            || [ "${platform}" = "NetBSD" ] \
            || [ "${platform}" = "OpenBSD" ]; then
            cmd="$CMD_TOP -b -d 1"
         fi
         $cmd | sed -e 's# *$##g' -e '/./{H;$!d;}' -e 'x;/PID/!d;' | grep . | head > "$top_processes_file"
      fi
   fi
}

notable_processes_info () { local PTFUNCNAME=notable_processes_info;
   local notable_processes_file="$1"
   local skip="${2:-"$PT_SUMMARY_SKIP"}"

   if echo "${skip}" | grep -v PROCESS >/dev/null; then
      local format="%5s    %+2d    %s\n"
      local sshd_pid=$(_pidof "/usr/sbin/sshd")

      echo "  PID    OOM    COMMAND" > "$notable_processes_file"

      # First, let's find the oom value of sshd
      if [ "$sshd_pid" ]; then
         printf "$format" $sshd_pid $(get_oom_of_pid $sshd_pid) "sshd" >> "$notable_processes_file"
      else
         printf "%5s    %3s    %s\n" "?" "?" "sshd doesn't appear to be running"  >> "$notable_processes_file"
      fi

      # Disabling PTDEBUG for the remainder of this function, otherwise we get several
      # hundred linebs of mostly useless debug output
      local PTDEBUG=""
      # Let's find out if any process has an oom of -17
      ps -eo pid,ucomm | tail -n +2 | while read pid proc; do
         # Skip sshd, since we manually checked this before
         [ "$sshd_pid" ] && [ "$sshd_pid" = "$pid" ] && continue
         local oom="$(get_oom_of_pid $pid)"
         if [ "$oom" ] && [ "$oom" != "?" ] && [ "$oom" = "-17" ]; then
            printf "$format" $pid $oom $proc >> "$notable_processes_file"
         fi
      done
   fi
}

processor_info () { local FUNCNAME=processor_info;
   local data_dir="$1"
   if [ -f /proc/cpuinfo ]; then
      _d "Got /proc/cpuinfo, copying that"
      cat /proc/cpuinfo > "$data_dir/proc_cpuinfo_copy" 2>/dev/null
   elif [ "${platform}" = "SunOS" ]; then
      _d "On SunOS, using psrinfo"
      $CMD_PSRINFO -v > "$data_dir/psrinfo_minus_v"
   fi 
}

# ########################################################################
# Attempt to get, parse, and print RAID controller status from possibly
# proprietary management software.  Any executables that are normally stored
# in a weird location, such as /usr/StorMan/arcconf, should have their
# location added to $PATH at the beginning of main().
# ########################################################################
propietary_raid_controller () { local FUNCNAME=propietary_raid_controller;
   local file="$1"
   local variable_file="$2"
   local data_dir="$3"
   local controller="$4"

   rm -f "$file"
   touch "$file"

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
