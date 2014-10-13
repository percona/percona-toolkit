# This program is copyright 2011 Percona Inc.
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
# report_system_info package
# ###########################################################################

# Package: report_system_info
# 

set -u

# ##############################################################################
# Functions for parsing specific files and getting desired info from them.
# These are called from within report_system_summary() and are separated so
# they can be tested easily.
# ##############################################################################
   
# ##############################################################################
# Parse Linux's /proc/cpuinfo.
# ##############################################################################
parse_proc_cpuinfo () { local PTFUNCNAME=parse_proc_cpuinfo;
   local file="$1"
   # Physical processors are indicated by distinct 'physical id'.  Virtual CPUs
   # are indicated by paragraphs -- one per paragraph.  We assume that all
   # processors are identical, i.e. that there are not some processors with dual
   # cores and some with quad cores.
   local virtual="$(grep -c ^processor "${file}")";
   local physical="$(grep 'physical id' "${file}" | sort -u | wc -l)";
   local cores="$(grep 'cpu cores' "${file}" | head -n 1 | cut -d: -f2)";

   # Older kernel won't have 'physical id' or 'cpu cores'.
   [ "${physical}" = "0" ] && physical="${virtual}"
   [ -z "${cores}" ] && cores=0

   # Test for HTT; cannot trust the 'ht' flag.  If physical * cores < virtual,
   # then hyperthreading is in use.
   cores=$((${cores} * ${physical}));
   local htt=""
   if [ ${cores} -gt 0 -a $cores -lt $virtual ]; then htt=yes; else htt=no; fi

   name_val "Processors" "physical = ${physical}, cores = ${cores}, virtual = ${virtual}, hyperthreading = ${htt}"

   awk -F: '/cpu MHz/{print $2}' "${file}" \
      | sort | uniq -c > "$PT_TMPDIR/parse_proc_cpuinfo_cpu.unq"
   name_val "Speeds" "$(group_concat "$PT_TMPDIR/parse_proc_cpuinfo_cpu.unq")"

   awk -F: '/model name/{print $2}' "${file}" \
      | sort | uniq -c > "$PT_TMPDIR/parse_proc_cpuinfo_model.unq"
   name_val "Models" "$(group_concat "$PT_TMPDIR/parse_proc_cpuinfo_model.unq")"

   awk -F: '/cache size/{print $2}' "${file}" \
      | sort | uniq -c > "$PT_TMPDIR/parse_proc_cpuinfo_cache.unq"
   name_val "Caches" "$(group_concat "$PT_TMPDIR/parse_proc_cpuinfo_cache.unq")"
}

# ##############################################################################
# Parse sysctl -a output on FreeBSD, and format it as CPU info.  The file is the
# first argument.
# ##############################################################################
parse_sysctl_cpu_freebsd() { local PTFUNCNAME=parse_sysctl_cpu_freebsd;
   local file="$1"
   [ -e "$file" ] || return;
   local virtual="$(awk '/hw.ncpu/{print $2}' "$file")"
   name_val "Processors" "virtual = ${virtual}"
   name_val "Speeds" "$(awk '/hw.clockrate/{print $2}' "$file")"
   name_val "Models" "$(awk -F: '/hw.model/{print substr($2, 2)}' "$file")"
}

# ##############################################################################
# Parse sysctl -a output on NetBSD.
# ##############################################################################
parse_sysctl_cpu_netbsd() { local PTFUNCNAME=parse_sysctl_cpu_netbsd;
   local file="$1"

   # return early if they didn't pass in a file
   [ -e "$file" ] || return

   local virtual="$(awk '/hw.ncpu /{print $NF}' "$file")"
   name_val "Processors" "virtual = ${virtual}"
   #name_val "Speeds" # TODO: No clue
   name_val "Models" "$(awk -F: '/hw.model/{print $3}' "$file")"
}

# ##############################################################################
# Detect cpu info on OpenBSD, and format it as CPU info
# ##############################################################################
parse_sysctl_cpu_openbsd() { local PTFUNCNAME=parse_sysctl_cpu_openbsd;
   local file="$1"

   [ -e "$file" ] || return

   name_val "Processors" "$(awk -F= '/hw.ncpu=/{print $2}' "$file")"
   name_val "Speeds" "$(awk -F= '/hw.cpuspeed/{print $2}' "$file")"
   name_val "Models" "$(awk -F= '/hw.model/{print substr($2, 1, index($2, " "))}' "$file")"
}

# ##############################################################################
# Parse CPU info from psrinfo -v
# ##############################################################################
parse_psrinfo_cpus() { local PTFUNCNAME=parse_psrinfo_cpus;
   local file="$1"

   [ -e "$file" ] || return

   name_val "Processors" "$(grep -c 'Status of .* processor' "$file")"
   awk '/operates at/ {
      start = index($0, " at ") + 4;
      end   = length($0) - start - 4
      print substr($0, start, end);
   }' "$file" | sort | uniq -c > "$PT_TMPDIR/parse_psrinfo_cpus.tmp"
   name_val "Speeds" "$(group_concat "$PT_TMPDIR/parse_psrinfo_cpus.tmp")"
}

# ##############################################################################
# Parse the output of 'free -b' plus the contents of /proc/meminfo
# ##############################################################################
parse_free_minus_b () { local PTFUNCNAME=parse_free_minus_b;
   local file="$1"

   [ -e "$file" ] || return

   local physical=$(awk '/Mem:/{print $3}' "${file}")
   local swap_alloc=$(awk '/Swap:/{print $2}' "${file}")
   local swap_used=$(awk '/Swap:/{print $3}' "${file}")
   local virtual=$(shorten $(($physical + $swap_used)) 1)

   name_val "Total"   $(shorten $(awk '/Mem:/{print $2}' "${file}") 1)
   name_val "Free"    $(shorten $(awk '/Mem:/{print $4}' "${file}") 1)
   name_val "Used"    "physical = $(shorten ${physical} 1), swap allocated = $(shorten ${swap_alloc} 1), swap used = $(shorten ${swap_used} 1), virtual = ${virtual}"
   name_val "Buffers" $(shorten $(awk '/Mem:/{print $6}' "${file}") 1)
   name_val "Caches"  $(shorten $(awk '/Mem:/{print $7}' "${file}") 1)
   name_val "Dirty"  "$(awk '/Dirty:/ {print $2, $3}' "${file}")"
}

# ##############################################################################
# Parse FreeBSD memory info from sysctl output.
# ##############################################################################
parse_memory_sysctl_freebsd() { local PTFUNCNAME=parse_memory_sysctl_freebsd;
   local file="$1"

   [ -e "$file" ] || return

   local physical=$(awk '/hw.realmem:/{print $2}' "${file}")
   local mem_hw=$(awk '/hw.physmem:/{print $2}' "${file}")
   local mem_used=$(awk '
      /hw.physmem/                   { mem_hw       = $2; }
      /vm.stats.vm.v_inactive_count/ { mem_inactive = $2; }
      /vm.stats.vm.v_cache_count/    { mem_cache    = $2; }
      /vm.stats.vm.v_free_count/     { mem_free     = $2; }
      /hw.pagesize/                  { pagesize     = $2; }
      END {
         mem_inactive *= pagesize;
         mem_cache    *= pagesize;
         mem_free     *= pagesize;
         print mem_hw - mem_inactive - mem_cache - mem_free;
      }
   ' "$file");
   name_val "Total"   $(shorten ${mem_hw} 1)
   name_val "Virtual" $(shorten ${physical} 1)
   name_val "Used"    $(shorten ${mem_used} 1)
}

# ##############################################################################
# Parse NetBSD memory info from sysctl output.
# ##############################################################################
parse_memory_sysctl_netbsd() { local PTFUNCNAME=parse_memory_sysctl_netbsd;
   local file="$1"
   local swapctl_file="$2"

   [ -e "$file" -a -e "$swapctl_file" ] || return

   local swap_mem="$(awk '{print $2*512}' "$swapctl_file")"
   name_val "Total"   $(shorten "$(awk '/hw.physmem /{print $NF}' "$file")" 1)
   name_val "User"    $(shorten "$(awk '/hw.usermem /{print $NF}' "$file")" 1)
   name_val "Swap"    $(shorten ${swap_mem} 1)
}

# ##############################################################################
# Parse OpenBSD memory info from sysctl output.
# ##############################################################################
parse_memory_sysctl_openbsd() { local PTFUNCNAME=parse_memory_sysctl_openbsd;
   local file="$1"
   local swapctl_file="$2"

   [ -e "$file" -a -e "$swapctl_file" ] || return

   local swap_mem="$(awk '{print $2*512}' "$swapctl_file")"
   name_val "Total"   $(shorten "$(awk -F= '/hw.physmem/{print $2}' "$file")" 1)
   name_val "User"    $(shorten "$(awk -F= '/hw.usermem/{print $2}' "$file")" 1)
   name_val "Swap"    $(shorten ${swap_mem} 1)
}

# ##############################################################################
# Parse memory devices from the output of 'dmidecode'.
# ##############################################################################
parse_dmidecode_mem_devices () { local PTFUNCNAME=parse_dmidecode_mem_devices;
   local file="$1"

   [ -e "$file" ] || return

   echo "  Locator   Size     Speed             Form Factor   Type          Type Detail"
   echo "  ========= ======== ================= ============= ============= ==========="
   # Print paragraphs containing 'Memory Device\n', extract the desired bits,
   # concatenate them into one long line, then format as a table.  The data
   # comes out in this order for each paragraph:
   # $2  Size         2048 MB
   # $3  Form Factor  <OUT OF SPEC>
   # $4  Locator      DIMM1
   # $5  Type         <OUT OF SPEC>
   # $6  Type Detail  Synchronous
   # $7  Speed        667 MHz (1.5 ns)
   sed    -e '/./{H;$!d;}' \
          -e 'x;/Memory Device\n/!d;' \
          -e 's/: /:/g' \
          -e 's/</{/g' \
          -e 's/>/}/g' \
          -e 's/[ \t]*\n/\n/g' \
       "${file}" \
       | awk -F: '/Size|Type|Form.Factor|Type.Detail|^[\t ]+Locator/{printf("|%s", $2)}/^[\t ]+Speed/{print "|" $2}' \
       | sed -e 's/No Module Installed/{EMPTY}/' \
       | sort \
       | awk -F'|' '{printf("  %-9s %-8s %-17s %-13s %-13s %-8s\n", $4, $2, $7, $3, $5, $6);}'
}

# ##############################################################################
# Parse the output of 'ip -s link'
# ##############################################################################
parse_ip_s_link () { local PTFUNCNAME=parse_ip_s_link;
   local file="$1"

   [ -e "$file" ] || return

   echo "  interface  rx_bytes rx_packets  rx_errors   tx_bytes tx_packets  tx_errors"
   echo "  ========= ========= ========== ========== ========== ========== =========="

   awk "/^[1-9][0-9]*:/ {
      save[\"iface\"] = substr(\$2, 1, index(\$2, \":\") - 1);
      new = 1;
   }
   \$0 !~ /[^0-9 ]/ {
      if ( new == 1 ) {
         new = 0;
         fuzzy_var = \$1; ${fuzzy_formula} save[\"bytes\"] = fuzzy_var;
         fuzzy_var = \$2; ${fuzzy_formula} save[\"packs\"] = fuzzy_var;
         fuzzy_var = \$3; ${fuzzy_formula} save[\"errs\"]  = fuzzy_var;
      }
      else {
         fuzzy_var = \$1; ${fuzzy_formula} tx_bytes   = fuzzy_var;
         fuzzy_var = \$2; ${fuzzy_formula} tx_packets = fuzzy_var;
         fuzzy_var = \$3; ${fuzzy_formula} tx_errors  = fuzzy_var;
         printf \"  %-8s %10.0f %10.0f %10.0f %10.0f %10.0f %10.0f\\n\", save[\"iface\"], save[\"bytes\"], save[\"packs\"], save[\"errs\"], tx_bytes, tx_packets, tx_errors;
      }
   }" "$file"
}

# ##############################################################################
# Parse the output of 'ethtool DEVICE'
# ##############################################################################
parse_ethtool () {
   local file="$1"

   [ -e "$file" ] || return

   echo "  Device    Speed     Duplex"
   echo "  ========= ========= ========="


   awk '
      /^Settings for / {
         device               = substr($3, 1, index($3, ":") ? index($3, ":")-1 : length($3));
         device_names[device] = device;
      }
      /Speed:/  { devices[device ",speed"]  = $2 }
      /Duplex:/ { devices[device ",duplex"] = $2 }
      END {
         for ( device in device_names ) {
            printf("  %-10s %-10s %-10s\n",
               device,
               devices[device ",speed"],
               devices[device ",duplex"]);
         }
      }
   ' "$file"

}

# ##############################################################################
# Parse the output of 'netstat -antp'
# ##############################################################################
parse_netstat () { local PTFUNCNAME=parse_netstat;
   local file="$1"

   [ -e "$file" ] || return

   echo "  Connections from remote IP addresses"
   awk '$1 ~ /^tcp/ && $5 ~ /^[1-9]/ {
      print substr($5, 1, index($5, ":") - 1);
   }' "${file}" | sort | uniq -c \
      | awk "{
         fuzzy_var=\$1;
         ${fuzzy_formula}
         printf \"    %-15s %5d\\n\", \$2, fuzzy_var;
         }" \
      | sort -n -t . -k 1,1 -k 2,2 -k 3,3 -k 4,4
   echo "  Connections to local IP addresses"
   awk '$1 ~ /^tcp/ && $5 ~ /^[1-9]/ {
      print substr($4, 1, index($4, ":") - 1);
   }' "${file}" | sort | uniq -c \
      | awk "{
         fuzzy_var=\$1;
         ${fuzzy_formula}
         printf \"    %-15s %5d\\n\", \$2, fuzzy_var;
         }" \
      | sort -n -t . -k 1,1 -k 2,2 -k 3,3 -k 4,4
   echo "  Connections to top 10 local ports"
   awk '$1 ~ /^tcp/ && $5 ~ /^[1-9]/ {
      print substr($4, index($4, ":") + 1);
   }' "${file}" | sort | uniq -c | sort -rn | head -n10 \
      | awk "{
         fuzzy_var=\$1;
         ${fuzzy_formula}
         printf \"    %-15s %5d\\n\", \$2, fuzzy_var;
         }" | sort
   echo "  States of connections"
   awk '$1 ~ /^tcp/ {
      print $6;
   }' "${file}" | sort | uniq -c | sort -rn \
      | awk "{
         fuzzy_var=\$1;
         ${fuzzy_formula}
         printf \"    %-15s %5d\\n\", \$2, fuzzy_var;
         }" | sort
}

# ##############################################################################
# Parse the joined output of 'mount' and 'df -hP'.  $1 = file; $2 = ostype.
# ##############################################################################
parse_filesystems () { local PTFUNCNAME=parse_filesystems;
   # Filesystem names and mountpoints can be very long.  We try to align things
   # as nicely as possible by making columns only as wide as needed.  This
   # requires two passes through the file.  The first pass finds the max size of
   # these columns and prints out a printf spec, and the second prints out the
   # file nicely aligned.
   local file="$1"
   local platform="$2"

   [ -e "$file" ] || return

   local spec="$(awk "
      BEGIN {
         device     = 10;
         fstype     = 4;
         options    = 4;
      }
      /./ {
         f_device     = \$1;
         f_fstype     = \$10;
         f_options    = substr(\$11, 2, length(\$11) - 2);
         if ( \"$2\" ~ /(Free|Open|Net)BSD/ ) {
            f_fstype  = substr(\$9, 2, length(\$9) - 2);
            f_options = substr(\$0, index(\$0, \",\") + 2);
            f_options = substr(f_options, 1, length(f_options) - 1);
         }
         if ( length(f_device) > device ) {
            device=length(f_device);
         }
         if ( length(f_fstype) > fstype ) {
            fstype=length(f_fstype);
         }
         if ( length(f_options) > options ) {
            options=length(f_options);
         }
      }
      END{
         print \"%-\" device \"s %5s %4s %-\" fstype \"s %-\" options \"s %s\";
      }
   " "${file}")"

   awk "
      BEGIN {
         spec=\"  ${spec}\\n\";
         printf spec, \"Filesystem\", \"Size\", \"Used\", \"Type\", \"Opts\", \"Mountpoint\";
      }
      {
         f_fstype     = \$10;
         f_options    = substr(\$11, 2, length(\$11) - 2);
         if ( \"$2\" ~ /(Free|Open|Net)BSD/ ) {
            f_fstype  = substr(\$9, 2, length(\$9) - 2);
            f_options = substr(\$0, index(\$0, \",\") + 2);
            f_options = substr(f_options, 1, length(f_options) - 1);
         }
         printf spec, \$1, \$2, \$5, f_fstype, f_options, \$6;
      }
   " "${file}"
}

# ##############################################################################
# Parse the output of fdisk -l, which should be in $PT_TMPDIR/percona-toolkit; there might be
# multiple fdisk -l outputs in the file.
# ##############################################################################
parse_fdisk () { local PTFUNCNAME=parse_fdisk;
   local file="$1"

   [ -e "$file" -a -s "$file" ] || return

   awk '
      BEGIN {
         format="%-12s %4s %10s %10s %18s\n";
         printf(format, "Device", "Type", "Start", "End", "Size");
         printf(format, "============", "====", "==========", "==========", "==================");
      }
      /Disk.*bytes/ {
         disk = substr($2, 1, length($2) - 1);
         size = $5;
         printf(format, disk, "Disk", "", "", size);
      }
      /Units/ {
         units = $9;
      }
      /^\/dev/ {
         if ( $2 == "*" ) {
            start = $3;
            end   = $4;
         }
         else {
            start = $2;
            end   = $3;
         }
         printf(format, $1, "Part", start, end, sprintf("%.0f", (end - start) * units));
      }
   ' "${file}"
}

# ##############################################################################
# Parse the output of lspci, and detect ethernet cards.
# ##############################################################################
parse_ethernet_controller_lspci () { local PTFUNCNAME=parse_ethernet_controller_lspci;
   local file="$1"

   [ -e "$file" ] || return

   grep -i ethernet "${file}" | cut -d: -f3 | while read line; do
      name_val "Controller" "${line}"
   done
}

# ##############################################################################
# Parse the output of "hpacucli ctrl all show config", which should be stored in
# $PT_TMPDIR/percona-toolkit
# ##############################################################################
parse_hpacucli () { local PTFUNCNAME=parse_hpacucli;
   local file="$1"
   [ -e "$file" ] || return
   grep 'logicaldrive\|physicaldrive' "${file}"
}

# ##############################################################################
# Parse the output of arcconf, which should be stored in $PT_TMPDIR/percona-toolkit
# ##############################################################################
parse_arcconf () { local PTFUNCNAME=parse_arcconf;
   local file="$1"

   [ -e "$file" ] || return

   local model="$(awk -F: '/Controller Model/{print $2}' "${file}")"
   local chan="$(awk -F: '/Channel description/{print $2}' "${file}")"
   local cache="$(awk -F: '/Installed memory/{print $2}' "${file}")"
   local status="$(awk -F: '/Controller Status/{print $2}' "${file}")"
   name_val "Specs" "$(echo "$model" | sed -e 's/ //'),${chan},${cache} cache,${status}"

   local battery=""
   if grep -q "ZMM" "$file"; then
      battery="$(grep -A2 'Controller ZMM Information' "$file" \
                  | awk '/Status/ {s=$4}
                         END      {printf "ZMM %s", s}')"
   else
      battery="$(grep -A5 'Controller Battery Info' "${file}" \
         | awk '/Capacity remaining/ {c=$4}
               /Status/             {s=$3}
               /Time remaining/     {t=sprintf("%dd%dh%dm", $7, $9, $11)}
               END                  {printf("%d%%, %s remaining, %s", c, t, s)}')"
   fi
   name_val "Battery" "${battery}"

   # ###########################################################################
   # Logical devices
   # ###########################################################################
   echo
   echo "  LogicalDev Size      RAID Disks Stripe Status  Cache"
   echo "  ========== ========= ==== ===== ====== ======= ======="
   for dev in $(awk '/Logical device number/{print $4}' "${file}"); do
      sed -n -e "/^Logical device .* ${dev}$/,/^$\|^Logical device number/p" "${file}" \
      | awk '
         /Logical device name/               {d=$5}
         /Size/                              {z=$3 " " $4}
         /RAID level/                        {r=$4}
         /Group [0-9]/                       {g++}
         /Stripe-unit size/                  {p=$4 " " $5}
         /Status of logical/                 {s=$6}
         /Write-cache mode.*Ena.*write-back/ {c="On (WB)"}
         /Write-cache mode.*Ena.*write-thro/ {c="On (WT)"}
         /Write-cache mode.*Disabled/        {c="Off"}
         END {
            printf("  %-10s %-9s %4d %5d %-6s %-7s %-7s\n",
               d, z, r, g, p, s, c);
         }'
   done

   # ###########################################################################
   # Physical devices
   # ###########################################################################
   echo
   echo "  PhysiclDev State   Speed         Vendor  Model        Size        Cache"
   echo "  ========== ======= ============= ======= ============ =========== ======="

   # Find the paragraph with physical devices, tabularize with assoc arrays.
   local tempresult=""
   sed -n -e '/Physical Device information/,/^$/p' "${file}" \
      | awk -F: '
         /Device #[0-9]/ {
            device=substr($0, index($0, "#"));
            devicenames[device]=device;
         }
         /Device is a/ {
            devices[device ",isa"] = substr($0, index($0, "is a") + 5);
         }
         /State/ {
            devices[device ",state"] = substr($2, 2);
         }
         /Transfer Speed/ {
            devices[device ",speed"] = substr($2, 2);
         }
         /Vendor/ {
            devices[device ",vendor"] = substr($2, 2);
         }
         /Model/ {
            devices[device ",model"] = substr($2, 2);
         }
         /Size/ {
            devices[device ",size"] = substr($2, 2);
         }
         /Write Cache/ {
            if ( $2 ~ /Enabled .write-back./ )
               devices[device ",cache"] = "On (WB)";
            else
               if ( $2 ~ /Enabled .write-th/ )
                  devices[device ",cache"] = "On (WT)";
               else
                  devices[device ",cache"] = "Off";
         }
         END {
            for ( device in devicenames ) {
               if ( devices[device ",isa"] ~ /Hard drive/ ) {
                  printf("  %-10s %-7s %-13s %-7s %-12s %-11s %-7s\n",
                     devices[device ",isa"],
                     devices[device ",state"],
                     devices[device ",speed"],
                     devices[device ",vendor"],
                     devices[device ",model"],
                     devices[device ",size"],
                     devices[device ",cache"]);
               }
            }
         }'
}

# ##############################################################################
# Parse the output of "lsiutil -i -s".
# ##############################################################################
# TODO This isn't used anywhere
parse_fusionmpt_lsiutil () { local PTFUNCNAME=parse_fusionmpt_lsiutil;
   local file="$1"
   echo
   awk '/LSI.*Firmware/ { print " ", $0 }' "${file}"
   grep . "${file}" | sed -n -e '/B___T___L/,$ {s/^/  /; p}'
}

# ##############################################################################
# Parse the output of MegaCli64 -AdpAllInfo -aALL
# ##############################################################################
# TODO why aren't we printing the latter half?
parse_lsi_megaraid_adapter_info () { local PTFUNCNAME=parse_lsi_megaraid_adapter_info;
   local file="$1"

   [ -e "$file" ] || return

   local name="$(awk -F: '/Product Name/{print substr($2, 2)}' "${file}")";
   local int=$(awk '/Host Interface/{print $4}' "${file}");
   local prt=$(awk '/Number of Backend Port/{print $5}' "${file}");
   local bbu=$(awk '/^BBU             :/{print $3}' "${file}");
   local mem=$(awk '/Memory Size/{print $4}' "${file}");
   local vdr=$(awk '/Virtual Drives/{print $4}' "${file}");
   local dvd=$(awk '/Degraded/{print $3}' "${file}");
   local phy=$(awk '/^  Disks/{print $3}' "${file}");
   local crd=$(awk '/Critical Disks/{print $4}' "${file}");
   local fad=$(awk '/Failed Disks/{print $4}' "${file}");

   name_val "Model" "${name}, ${int} interface, ${prt} ports"
   name_val "Cache" "${mem} Memory, BBU ${bbu}"
}

# ##############################################################################
# Parse the output of
# /opt/MegaRAID/MegaCli/MegaCli64 -AdpBbuCmd -GetBbuStatus -aALL
# ##############################################################################
parse_lsi_megaraid_bbu_status () { local PTFUNCNAME=parse_lsi_megaraid_bbu_status;
   local file="$1"

   [ -e "$file" ] || return

   local charge=$(awk '/Relative State/{print $5}' "${file}");
   local temp=$(awk '/^Temperature/{print $2}' "${file}");
   local soh=$(awk '/isSOHGood:/{print $2}' "${file}");
   name_val "BBU" "${charge}% Charged, Temperature ${temp}C, isSOHGood=${soh}"
}

# ##############################################################################
# Reports the output of lvs. Additionally, if the second argument is a file
# that contains the output of 'vgs -o vg_name,vg_size,vg_free', appends the
# total and free space available to each volume.
# ##############################################################################
format_lvs () { local PTFUNCNAME=format_lvs;
   local file="$1"
   if [ -e "$file" ]; then
      grep -v "open failed" "$file"
   else
      echo "Unable to collect information";
   fi
}

# ##############################################################################
# Parse physical devices from the output of
# /opt/MegaRAID/MegaCli/MegaCli64 -LdPdInfo -aALL
# OR, it will also work with the output of
# /opt/MegaRAID/MegaCli/MegaCli64 -PDList -aALL
# ##############################################################################
parse_lsi_megaraid_devices () { local PTFUNCNAME=parse_lsi_megaraid_devices;
   local file="$1"

   [ -e "$file" ] || return

   echo
   echo "  PhysiclDev Type State   Errors Vendor  Model        Size"
   echo "  ========== ==== ======= ====== ======= ============ ==========="
   for dev in $(awk '/Device Id/{print $3}' "${file}"); do
      sed -e '/./{H;$!d;}' -e "x;/Device Id: ${dev}/!d;" "${file}" \
      | awk '
         /Media Type/                        {d=substr($0, index($0, ":") + 2)}
         /PD Type/                           {t=$3}
         /Firmware state/                    {s=$3}
         /Media Error Count/                 {me=$4}
         /Other Error Count/                 {oe=$4}
         /Predictive Failure Count/          {pe=$4}
         /Inquiry Data/                      {v=$3; m=$4;}
         /Raw Size/                          {z=$3}
         END {
            printf("  %-10s %-4s %-7s %6s %-7s %-12s %-7s\n",
               substr(d, 1, 10), t, s, me "/" oe "/" pe, v, m, z);
         }'
   done
}

# ##############################################################################
# Parse virtual devices from the output of
# /opt/MegaRAID/MegaCli/MegaCli64 -LdPdInfo -aALL
# OR, it will also work with the output of
# /opt/MegaRAID/MegaCli/MegaCli64 -LDInfo -Lall -aAll
# ##############################################################################
parse_lsi_megaraid_virtual_devices () { local PTFUNCNAME=parse_lsi_megaraid_virtual_devices;
   local file="$1"

   [ -e "$file" ] || return

   # Somewhere on the Internet, I found the following guide to understanding the
   # RAID level, but I don't know the source anymore.
   #    Primary-0, Secondary-0, RAID Level Qualifier-0 = 0
   #    Primary-1, Secondary-0, RAID Level Qualifier-0 = 1
   #    Primary-5, Secondary-0, RAID Level Qualifier-3 = 5
   #    Primary-1, Secondary-3, RAID Level Qualifier-0 = 10
   # I am not sure if this is always correct or not (it seems correct).  The
   # terminology MegaRAID uses is not clear to me, and isn't documented that I
   # am aware of.  Anyone who can clarify the above, please contact me.
   echo
   echo "  VirtualDev Size      RAID Level Disks SpnDpth Stripe Status  Cache"
   echo "  ========== ========= ========== ===== ======= ====== ======= ========="
   awk '
      /^Virtual (Drive|Disk):/ {
         device              = $3;
         devicenames[device] = device;
      }
      /Number Of Drives/ {
         devices[device ",numdisks"] = substr($0, index($0, ":") + 1);
      }
      /^Name/ {
         devices[device ",name"] = substr($0, index($0, ":") + 1) > "" ? substr($0, index($0, ":") + 1) : "(no name)";
      }
      /RAID Level/ {
         devices[device ",primary"]   = substr($3, index($3, "-") + 1, 1);
         devices[device ",secondary"] = substr($4, index($4, "-") + 1, 1);
         devices[device ",qualifier"] = substr($NF, index($NF, "-") + 1, 1);
      }
      /Span Depth/ {
         devices[device ",spandepth"] = substr($2, index($2, ":") + 1);
      }
      /Number of Spans/ {
         devices[device ",numspans"] = $4;
      }
      /^Size/ {
         devices[device ",size"] = substr($0, index($0, ":") + 1);
      }
      /^State/ {
         devices[device ",state"] = substr($0, index($0, ":") + 2);
      }
      /^Stripe? Size/ {
         devices[device ",stripe"] = substr($0, index($0, ":") + 1);
      }
      /^Current Cache Policy/ {
         devices[device ",wpolicy"] = $4 ~ /WriteBack/ ? "WB" : "WT";
         devices[device ",rpolicy"] = $5 ~ /ReadAheadNone/ ? "no RA" : "RA";
      }
      END {
         for ( device in devicenames ) {
            raid = 0;
            if ( devices[device ",primary"] == 1 ) {
               raid = 1;
               if ( devices[device ",secondary"] == 3 ) {
                  raid = 10;
               }
            }
            else {
               if ( devices[device ",primary"] == 5 ) {
                  raid = 5;
               }
            }
            printf("  %-10s %-9s %-10s %5d %7s %6s %-7s %s\n",
               device devices[device ",name"],
               devices[device ",size"],
               raid " (" devices[device ",primary"] "-" devices[device ",secondary"] "-" devices[device ",qualifier"] ")",
               devices[device ",numdisks"],
               devices[device ",spandepth"] "-" devices[device ",numspans"],
               devices[device ",stripe"], devices[device ",state"],
               devices[device ",wpolicy"] ", " devices[device ",rpolicy"]);
         }
      }' "${file}"
}

# ##############################################################################
# Simplifies vmstat and aligns it nicely.  We don't need the memory stats, the
# system activity is enough.
# ##############################################################################
format_vmstat () { local PTFUNCNAME=format_vmstat;
   local file="$1"

   [ -e "$file" ] || return

   awk "
      BEGIN {
         format = \"  %2s %2s  %4s %4s %5s %5s %6s %6s %3s %3s %3s %3s %3s\n\";
      }
      /procs/ {
         print  \"  procs  ---swap-- -----io---- ---system---- --------cpu--------\";
      }
      /bo/ {
         printf format, \"r\", \"b\", \"si\", \"so\", \"bi\", \"bo\", \"ir\", \"cs\", \"us\", \"sy\", \"il\", \"wa\", \"st\";
      }
      \$0 !~ /r/ {
            fuzzy_var = \$1;   ${fuzzy_formula}  r   = fuzzy_var;
            fuzzy_var = \$2;   ${fuzzy_formula}  b   = fuzzy_var;
            fuzzy_var = \$7;   ${fuzzy_formula}  si  = fuzzy_var;
            fuzzy_var = \$8;   ${fuzzy_formula}  so  = fuzzy_var;
            fuzzy_var = \$9;   ${fuzzy_formula}  bi  = fuzzy_var;
            fuzzy_var = \$10;  ${fuzzy_formula}  bo  = fuzzy_var;
            fuzzy_var = \$11;  ${fuzzy_formula}  ir  = fuzzy_var;
            fuzzy_var = \$12;  ${fuzzy_formula}  cs  = fuzzy_var;
            fuzzy_var = \$13;                    us  = fuzzy_var;
            fuzzy_var = \$14;                    sy  = fuzzy_var;
            fuzzy_var = \$15;                    il  = fuzzy_var;
            fuzzy_var = \$16;                    wa  = fuzzy_var;
            fuzzy_var = \$17;                    st  = fuzzy_var;
            printf format, r, b, si, so, bi, bo, ir, cs, us, sy, il, wa, st;
         }
   " "${file}"
}

processes_section () { local PTFUNCNAME=processes_section;
   local top_process_file="$1"
   local notable_procs_file="$2"
   local vmstat_file="$3"
   local platform="$4"

   section "Top Processes"
   cat "$top_process_file"
   section "Notable Processes"
   cat "$notable_procs_file"
   if [ -e "$vmstat_file" ]; then
      section "Simplified and fuzzy rounded vmstat (wait please)"
      wait # For the process we forked that was gathering vmstat samples
      if [ "${platform}" = "Linux" ]; then
         format_vmstat "$vmstat_file"
      else
         # TODO: simplify/format for other platforms
         cat "$vmstat_file"
      fi
   fi
}

section_Processor () {
   local platform="$1"
   local data_dir="$2"

   section "Processor"

   if [ -e "$data_dir/proc_cpuinfo_copy" ]; then
      parse_proc_cpuinfo "$data_dir/proc_cpuinfo_copy"
   elif [ "${platform}" = "FreeBSD" ]; then
      parse_sysctl_cpu_freebsd "$data_dir/sysctl"
   elif [ "${platform}" = "NetBSD" ]; then
      parse_sysctl_cpu_netbsd "$data_dir/sysctl"
   elif [ "${platform}" = "OpenBSD" ]; then
      parse_sysctl_cpu_openbsd "$data_dir/sysctl"
   elif [ "${platform}" = "SunOS" ]; then
      parse_psrinfo_cpus "$data_dir/psrinfo_minus_v"
      # TODO: prtconf -v actually prints the CPU model name etc.
   fi
}

section_Memory () {
   local platform="$1"
   local data_dir="$2"

   section "Memory"
   if [ "${platform}" = "Linux" ]; then
      parse_free_minus_b "$data_dir/memory"
   elif [ "${platform}" = "FreeBSD" ]; then
      parse_memory_sysctl_freebsd "$data_dir/sysctl"
   elif [ "${platform}" = "NetBSD" ]; then
      parse_memory_sysctl_netbsd "$data_dir/sysctl" "$data_dir/swapctl"
   elif [ "${platform}" = "OpenBSD" ]; then
      parse_memory_sysctl_openbsd "$data_dir/sysctl" "$data_dir/swapctl"
   elif [ "${platform}" = "SunOS" ]; then
      name_val "Memory" "$(cat "$data_dir/memory")"
   fi

   local rss=$( get_var "rss" "$data_dir/summary" )
   name_val "UsedRSS" "$(shorten ${rss} 1)"

   if [ "${platform}" = "Linux" ]; then
      name_val "Swappiness" "$(get_var "swappiness" "$data_dir/summary")"
      name_val "DirtyPolicy" "$(get_var "dirtypolicy" "$data_dir/summary")"
      local dirty_status="$(get_var "dirtystatus" "$data_dir/summary")"
      if [ -n "$dirty_status" ]; then
         name_val "DirtyStatus" "$dirty_status"
      fi
   fi

   if [ -s "$data_dir/dmidecode" ]; then
      parse_dmidecode_mem_devices "$data_dir/dmidecode"
   fi
}

parse_uptime () {
   local file="$1"

   awk ' / up / {
            printf substr($0, index($0, " up ")+4 );
         }
         !/ up / {
            printf $0;
         }
' "$file"
}

report_fio_minus_a () {
   local file="$1"

   name_val "fio Driver" "$(get_var driver_version "$file")"
   
   local adapters="$( get_var "adapters" "$file" )"
   for adapter in $( echo $adapters | awk '{for (i=1; i<=NF; i++) print $i;}' ); do
      local adapter_for_output="$(echo "$adapter" | sed 's/::[0-9]*$//' | tr ':' ' ')"
      name_val "$adapter_for_output"         "$(get_var "${adapter}_general" "$file")"

      local modules="$(get_var "${adapter}_modules" "$file")"
      for module in $( echo $modules | awk '{for (i=1; i<=NF; i++) print $i;}' ); do
         local name_val_len_orig=$NAME_VAL_LEN;
         local NAME_VAL_LEN=16
         name_val "$module" "$(get_var "${adapter}_${module}_attached_as"  "$file")"
         name_val ""              "$(get_var "${adapter}_${module}_general"      "$file")"
         name_val ""              "$(get_var "${adapter}_${module}_firmware"     "$file")"
         name_val ""              "$(get_var "${adapter}_${module}_temperature"  "$file")"
         name_val ""              "$(get_var "${adapter}_${module}_media_status" "$file")"
         if [ "$(get_var "${adapter}_${module}_rated_pbw" "$file")" ]; then
            name_val ""           "$(get_var "${adapter}_${module}_rated_pbw" "$file")"
         fi
         local NAME_VAL_LEN=$name_val_len_orig;
      done
   done
}

# The sum of all of the above
report_system_summary () { local PTFUNCNAME=report_system_summary;
   local data_dir="$1"

   section "Percona Toolkit System Summary Report"

   # ########################################################################
   # General date, time, load, etc
   # ########################################################################

   [ -e "$data_dir/summary" ] \
      || die "The data directory doesn't have a summary file, exiting."

   local platform="$(get_var "platform" "$data_dir/summary")"
   name_val "Date" "`date -u +'%F %T UTC'` (local TZ: `date +'%Z %z'`)"
   name_val "Hostname" "$(get_var hostname "$data_dir/summary")"
   name_val "Uptime" "$(parse_uptime "$data_dir/uptime")"

   if [ "$(get_var "vendor" "$data_dir/summary")" ]; then
      name_val "System" "$(get_var "system" "$data_dir/summary")";
      name_val "Service Tag" "$(get_var "servicetag" "$data_dir/summary")";
   fi

   name_val "Platform" "${platform}"
   local zonename="$(get_var zonename "$data_dir/summary")";
   [ -n "${zonename}" ] && name_val "Zonename" "$zonename"

   name_val "Release" "$(get_var "release" "$data_dir/summary")"
   name_val "Kernel" "$(get_var "kernel" "$data_dir/summary")"

   name_val "Architecture" "CPU = $(get_var "CPU_ARCH" "$data_dir/summary"), OS = $(get_var "OS_ARCH" "$data_dir/summary")"

   local threading="$(get_var threading "$data_dir/summary")"
   local compiler="$(get_var compiler "$data_dir/summary")"
   [ -n "$threading" ] && name_val "Threading" "$threading"
   [ -n "$compiler"  ] && name_val "Compiler" "$compiler"

   local getenforce="$(get_var getenforce "$data_dir/summary")"
   [ -n "$getenforce" ] && name_val "SELinux" "${getenforce}";

   name_val "Virtualized" "$(get_var "virt" "$data_dir/summary")"

   # ########################################################################
   # Processor/CPU, Memory, Swappiness, dmidecode
   # ########################################################################
   section_Processor "$platform" "$data_dir"

   section_Memory    "$platform" "$data_dir"

   # ########################################################################
   # Disks, RAID, Filesystems
   # ########################################################################
   # TODO: Add info about software RAID

   if [ -s "$data_dir/fusion-io_card" ]; then
      section "Fusion-io Card"
      report_fio_minus_a "$data_dir/fusion-io_card"
   fi
   
   if [ -s "$data_dir/mounted_fs" ]; then
      section "Mounted Filesystems"
      parse_filesystems "$data_dir/mounted_fs" "${platform}"
   fi

   if [ "${platform}" = "Linux" ]; then

      section "Disk Schedulers And Queue Size"
      local disks="$( get_var "internal::disks" "$data_dir/summary" )"
      for disk in $disks; do
         local scheduler="$( get_var "internal::${disk}" "$data_dir/summary" )"
         name_val "${disk}" "${scheduler:-"UNREADABLE"}"
      done

      section "Disk Partioning"
      parse_fdisk "$data_dir/partitioning"

      section "Kernel Inode State"
      for file in dentry-state file-nr inode-nr; do
         name_val "${file}" "$(get_var "${file}" "$data_dir/summary")"
      done

      section "LVM Volumes"
      format_lvs "$data_dir/lvs"
      section "LVM Volume Groups"
      format_lvs "$data_dir/vgs"
   fi

   section "RAID Controller"
   local controller="$(get_var "raid_controller" "$data_dir/summary")"
   name_val "Controller" "$controller"
   local key="$(get_var "internal::raid_opt" "$data_dir/summary")"
   case "$key" in
      0)
         # Not found
         cat "$data_dir/raid-controller"
         ;;
      1)
         parse_arcconf "$data_dir/raid-controller"
         ;;
      2)
         parse_hpacucli "$data_dir/raid-controller"
         ;;
      3)
      # TODO: This is pretty bad form, but seeing how the three forms
      # aren't mutually exclusive, I can't come up with a better way.
         [ -e "$data_dir/lsi_megaraid_adapter_info.tmp" ] && \
            parse_lsi_megaraid_adapter_info "$data_dir/lsi_megaraid_adapter_info.tmp"
         [ -e "$data_dir/lsi_megaraid_bbu_status.tmp" ] && \
            parse_lsi_megaraid_bbu_status "$data_dir/lsi_megaraid_bbu_status.tmp"
         if [ -e "$data_dir/lsi_megaraid_devices.tmp" ]; then
            parse_lsi_megaraid_virtual_devices "$data_dir/lsi_megaraid_devices.tmp"
            parse_lsi_megaraid_devices "$data_dir/lsi_megaraid_devices.tmp"
         fi
         ;;
   esac

   if [ "${OPT_SUMMARIZE_NETWORK}" ]; then
      # #####################################################################
      # Network stuff
      # #####################################################################
      if [ "${platform}" = "Linux" ]; then
         section "Network Config"
         if [ -s "$data_dir/lspci_file" ]; then
            parse_ethernet_controller_lspci "$data_dir/lspci_file"
         fi
         if grep "net.ipv4.tcp_fin_timeout" "$data_dir/sysctl" > /dev/null 2>&1; then
            name_val "FIN Timeout" "$(awk '/net.ipv4.tcp_fin_timeout/{print $NF}' "$data_dir/sysctl")"
            name_val "Port Range" "$(awk '/net.ipv4.ip_local_port_range/{print $NF}' "$data_dir/sysctl")"
         fi
      fi

      # TODO cat /proc/sys/net/ipv4/ip_conntrack_max ; it might be
      # /proc/sys/net/netfilter/nf_conntrack_max or /proc/sys/net/nf_conntrack_max
      # in new kernels like Fedora 12?

      if [ -s "$data_dir/ip" ]; then
         section "Interface Statistics"
         parse_ip_s_link "$data_dir/ip"
      fi

      if [ -s "$data_dir/network_devices" ]; then
         section "Network Devices"
         parse_ethtool "$data_dir/network_devices"
      fi

      if [ "${platform}" = "Linux" -a -e "$data_dir/netstat" ]; then
         section "Network Connections"
         parse_netstat "$data_dir/netstat"
      fi
   fi

   # ########################################################################
   # Processes, load, etc
   # ########################################################################
   [ "$OPT_SUMMARIZE_PROCESSES" ] && processes_section           \
                                       "$data_dir/processes"     \
                                       "$data_dir/notable_procs" \
                                       "$data_dir/vmstat"        \
                                       "$platform"

   # ########################################################################
   # All done.  Signal the end so it's explicit.
   # ########################################################################
   section "The End"
}

# ###########################################################################
# End report_system_info package
# ###########################################################################
