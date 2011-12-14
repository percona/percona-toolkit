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
# safeguards package
# ###########################################################################

# Package: safeguards
# safeguards is a collection of function to help avoid blowing things up.

set -u

disk_space() {
   local filesystem=${1:-"$PWD"}
   # Filesystem   1M-blocks  Used Available Capacity  Mounted on
   # /dev/disk0s2    115383 92637     22496    81%    /
   df -m $filesystem
}

# Sub: check_disk_space
#   Check if there is or will be enough disk space.
#
# Arguments:
#   file   - File with output from <disk_space()>.
#   mb     - Minimum MB free.
#   pc     - Minimum percent free.
#   margin - Add this many MB to the real MB used.
#
# Returns:
#   0 if there is/will be enough disk space, else 1.
check_disk_space() {
   local file=$1
   local mb=${2:-"0"}
   local pc=${3:-"0"}
   local margin=${4:-"0"}

   local mb_used=$(cat $file | awk '/^\//{print $3}');
   local mb_free=$(cat $file | awk '/^\//{print $4}');
   local pc_used=$(cat $file | awk '/^\//{print $5}' | sed -e 's/%//g');

   if [ "$margin" -gt "0" ]; then
      local mb_total=$(($mb_used + $mb_free))

      mb_used=$(($mb_used + $margin))
      mb_free=$(($mb_free - $margin))
      pc_used=$(awk "BEGIN { printf(\"%d\", $mb_used/$mb_total * 100) }")
   fi

   local pc_free=$((100 - $pc_used))

   if [ "$mb_free" -le "$mb" -o "$pc_free" -le "$pc" ]; then
      warn "Not enough free disk space: ${pc_free}% free, ${mb_free} MB free; wanted more than ${pc}% free or ${mb} MB free"
      return 1
   fi

   return 0
}

# ###########################################################################
# End safeguards package
# ###########################################################################
