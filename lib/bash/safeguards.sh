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
# safeguards package
# ###########################################################################

# Package: safeguards
# safeguards is a collection of function to help avoid blowing things up.

set -u

disk_space() {
   local filesystem="${1:-$PWD}"
   # Filesystem   1024-blocks     Used Available Capacity  Mounted on
   # /dev/disk0s2   118153176 94409664  23487512    81%    /
   df -P -k "$filesystem"
}

# Sub: check_disk_space
#   Check if there is or will be enough disk space.  Input is a file
#   with output from <disk_space()>, i.e. `df -P -k`.  The df output
#   must use 1k blocks, which should be POSIX standard.
#
# Arguments:
#   file           - File with output from <disk_space()>.
#   min_free_bytes - Minimum free bytes.
#   min_free_pct   - Minimum free percentage.
#   bytes_margin   - Add this many bytes to the real bytes used.
#
# Returns:
#   0 if there is/will be enough disk space, else 1.
check_disk_space() {
   local file="$1"
   local min_free_bytes="${2:-0}"
   local min_free_pct="${3:-0}"
   local bytes_margin="${4:-0}"

   # Real/actual bytes used and bytes free.
   local used_bytes=$(tail -n 1 "$file" | perl -ane 'print $F[2] * 1024')
   local free_bytes=$(tail -n 1 "$file" | perl -ane 'print $F[3] * 1024')
   local pct_used=$(tail -n 1 "$file" | perl -ane 'print ($F[4] =~ m/(\d+)/)')
   local pct_free=$((100 - $pct_used))

   # Report the real values to the user.
   local real_free_bytes=$free_bytes
   local real_pct_free=$pct_free

   # If there's a margin, we need to adjust the real values.
   if [ $bytes_margin -gt 0 ]; then
      used_bytes=$(($used_bytes + $bytes_margin))
      free_bytes=$(($free_bytes - $bytes_margin))
      pct_used=$(perl -e "print int(($used_bytes/($used_bytes + $free_bytes)) * 100)")

      pct_free=$((100 - $pct_used))
   fi

   if [ $free_bytes -lt $min_free_bytes -o $pct_free -lt $min_free_pct ]; then
      warn "Not enough free disk space:
    Limit: ${min_free_pct}% free, ${min_free_bytes} bytes free
   Actual: ${real_pct_free}% free, ${real_free_bytes} bytes free (- $bytes_margin bytes margin)
"
      # Print the df that we used.
      cat "$file" >&2

      return 1  # not enough disk space
   fi

   return 0  # disk space is OK
}

# ###########################################################################
# End safeguards package
# ###########################################################################
