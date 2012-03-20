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
CMD_TOP="$(_which top 2>/dev/null)"
CMD_VMSTAT="$(_which vmstat 2>/dev/null)"
CMD_IP="$( _which ip 2>/dev/null )"
CMD_NETSTAT="$( _which netstat 2>/dev/null )"

collect_system_data () {
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

   if [ "${platform}" = "SunOS" ]; then
      if [ -n "${CMD_ZONENAME}" ]; then
         echo "zonename    $($CMD_ZONENAME)" >> "$data_dir/summary"
      fi
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

   fi

   if [ -n "$CMD_IP" ] && echo "${PT_SUMMARY_SKIP}" | grep -v NETWORK >/dev/null; then
      $CMD_IP -s link > "$data_dir/ip"
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

# Try to find all sorts of different files that say what the release is.
find_release_and_kernel () {
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
   elif [ "${platform}" = "FreeBSD" ]; then
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

cpu_and_os_arch () {
   local file="$1"
   local platform="$2"

   local CPU_ARCH='32-bit'
   local OS_ARCH='32-bit'
   if [ "${platform}" = "Linux" ]; then
      if [ "$(grep -q ' lm ' /proc/cpuinfo)" ]; then
         CPU_ARCH='64-bit'
      fi
   elif [ "${platform}" = "FreeBSD" ]; then
      if $CMD_SYSCTL hw.machine_arch | grep -v 'i[36]86' >/dev/null; then
         CPU_ARCH='64-bit'
      fi
   elif [ "${platform}" = "SunOS" ]; then
      if isainfo -b | grep 64 >/dev/null ; then
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
find_virtualization () {
   local vars_file="$1"
   local platform="$2"
   local dmesg_file="$3"
   local lspci_file="$4"

   local tempfile="$TMPDIR/find_virtualziation.tmp"

   local virt=""
   if [ -s "$dmesg_file" ]; then
      virt="$(parse_virtualization_dmesg "$dmesg_file")"
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
         virt="$(parse_virtualization_generic "$tempfile" )"
      elif [ -n "$CMD_SMBIOS" ] && $CMD_SMBIOS > "$tempfile" 2>/dev/null; then
         virt="$(parse_virtualization_generic "$tempfile" )"
      fi
   elif [ -e /proc/user_beancounters ]; then
      virt="OpenVZ/Virtuozzo"
   fi
   echo "virt    ${virt:-No virtualization detected}" >> "$vars_file"
}

# TODO: Maybe worth it to just dump dmidecode once and parse that?
dmidecode_system_info () {
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

find_memory_stats () {
   local file="$1"
   local platform="$2"

   if [ "${platform}" = "Linux" ]; then
      free -b > "$file"
      cat /proc/meminfo >> "$file"
   elif [ "${platform}" = "SunOS" ]; then
      $CMD_PRTCONF | awk -F: '/Memory/{print $2}' > "$file"
   fi
}

mounted_fs_info () {
   local file="$1"
   local platform="$2"
   local skip="${3:-$PT_SUMMARY_SKIP}"

   if echo "${skip}" | grep -v MOUNT >/dev/null; then
      if [ "${platform}" != "SunOS" ]; then
         local cmd="df -h"
         if [ "${platform}" = "Linux" ]; then
            cmd="df -h -P"
         fi
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
raid_controller () {
   local file="$1"
   local dmesg_file="$2"
   local lspci_file="$3"

   local tempfile="$TMPDIR/raid_controller.tmp"

   local controller=""
   if [ -s "$lspci_file" ]; then
      controller="$(parse_raid_controller_lspci "$lspci_file")"
   fi
   if [ -z "${controller}" ] && [ -s "$dmesg_file" ]; then
      controller="$(parse_raid_controller_dmesg "$dmesg_file")"
   fi

   echo "raid_controller    ${controller:-No RAID controller detected}" >> "$file"
}

schedulers_and_queue_size () {
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

top_processes () {
   local top_processes_file="$1"
   local skip="${2:-"$PT_SUMMARY_SKIP"}"

   if echo "${skip}" | grep -v PROCESS >/dev/null; then
      if [ -n "$CMD_PRSTAT" ]; then
         $CMD_PRSTAT | head > "$top_processes_file"
      elif [ -n "$CMD_TOP" ]; then
         local cmd="$CMD_TOP -bn 1"
         if [ "${platform}" = "FreeBSD" ]; then
            cmd="$CMD_TOP -b -d 1"
         fi
         $cmd | sed -e 's# *$##g' -e '/./{H;$!d;}' -e 'x;/PID/!d;' | grep . | head > "$top_processes_file"
      fi
   fi
}

notable_processes_info () {
   local notable_processes_file="$1"
   local skip="${2:-"$PT_SUMMARY_SKIP"}"

   if echo "${skip}" | grep -v PROCESS >/dev/null; then
      local sshd_pid=$(_pidof sshd)

      echo "  PID    OOM    COMMAND" > "$notable_processes_file"

      # First, let's find the oom value of sshd
      if [ "$sshd_pid" ]; then
         echo "$sshd_pid    $(get_oom_of_pid $sshd_pid) sshd" >> "$notable_processes_file"
      else
         _d "sshd doesn't appear to be running"
      fi

      # Now, let's find if any process has an oom value of -17
      ps -eo pid,ucomm | tail -n +2 | while read pid proc; do
         [ "$proc" = "sshd" ] && continue
         local oom=$(get_oom_of_pid $pid)
         if [ "$oom" ] && [ "$oom" != "?" ] && [ "$oom" -eq -17 ]; then
            printf "%5s    %+2d    %s\n" $pid $oom $proc >> "$notable_processes_file"
         fi
      done
   fi
}

processor_info () {
   local data_dir="$1"
   if [ -f /proc/cpuinfo ]; then
      cat /proc/cpuinfo > "$data_dir/proc_cpuinfo_copy" 2>/dev/null
   elif [ "${platform}" = "SunOS" ]; then
      psrinfo -v > "$data_dir/psrinfo_minus_v"
   fi 
}

# ########################################################################
# Attempt to get, parse, and print RAID controller status from possibly
# proprietary management software.  Any executables that are normally stored
# in a weird location, such as /usr/StorMan/arcconf, should have their
# location added to $PATH at the beginning of main().
# ########################################################################
propietary_raid_controller () {
   local file="$1"
   local variable_file="$2"
   local data_dir="$3"
   local controller="$4"

   rm -f "$file"
   touch "$file"

   notfound=""
   if [ "${controller}" = "AACRAID" ]; then
      if ! _which arcconf >/dev/null 2>&1; then
         notfound="e.g. http://www.adaptec.com/en-US/support/raid/scsi_raid/ASR-2120S/"
      elif arcconf getconfig 1 > "$file" 2>/dev/null; then
         echo "internal::raid_opt    1" >> "$variable_file"
      fi
   elif [ "${controller}" = "HP Smart Array" ]; then
      if ! _which hpacucli >/dev/null 2>&1; then
         notfound="your package repository or the manufacturer's website"
      elif hpacucli ctrl all show config > "$file" 2>/dev/null; then
         echo "internal::raid_opt    2" >> "$variable_file"
      fi
   elif [ "${controller}" = "LSI Logic MegaRAID SAS" ]; then
      if ! _which MegaCli64 >/dev/null 2>&1; then 
         notfound="your package repository or the manufacturer's website"
      else
         echo "internal::raid_opt    3" >> "$variable_file"
         MegaCli64 -AdpAllInfo -aALL -NoLog > "$data_dir/lsi_megaraid_adapter_info.tmp" 2>/dev/null
         MegaCli64 -AdpBbuCmd -GetBbuStatus -aALL -NoLog > "$data_dir/lsi_megaraid_bbu_status.tmp" 2>/dev/null
         MegaCli64 -LdPdInfo -aALL -NoLog > "$data_dir/lsi_megaraid_devices.tmp" 2>/dev/null
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
