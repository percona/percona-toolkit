# This program is copyright 2011-2026 Percona LLC and/or its affiliates.
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
# You should have received a copy of the GNU General Public License, version 2
# along with this program; if not, see <https://www.gnu.org/licenses/>.
# ###########################################################################
# tmpdir package
# ###########################################################################

# Package: tmpdir
# tmpdir make a secure temporary directory using mktemp.

set -u

# Global variables.
PT_TMPDIR=""

# Sub: mk_tmpdir
#   Create a secure tmpdir and set PT_TMPDIR.
#
# Optional Arguments:
#   dir - User-specified tmpdir (default none).
#
# Set Global Variables:
#   PT_TMPDIR - Absolute path of secure temp directory.
mk_tmpdir() {
   local dir="${1:-""}"

   if [ -n "$dir" ]; then
      if [ ! -d "$dir" ]; then
         mkdir "$dir" || die "Cannot make tmpdir $dir"
      fi
      PT_TMPDIR="$dir"
   else
      local tool="${0##*/}"
      local pid="$$"
      PT_TMPDIR=`mktemp -d -t "${tool}.${pid}.XXXXXX"` \
         || die "Cannot make secure tmpdir"
   fi
}

# Sub: rm_tmpdir
#   Remove the tmpdir and unset PT_TMPDIR.
#
# Optional Global Variables:
#   PT_TMPDIR - PT_TMPDIR set by <mk_tmpdir()>.
#
# Set Global Variables:
#   PT_TMPDIR - Set to "".
rm_tmpdir() {
   if [ -n "$PT_TMPDIR" ] && [ -d "$PT_TMPDIR" ]; then
      rm -rf "$PT_TMPDIR"
   fi
   PT_TMPDIR=""
}

# ###########################################################################
# End tmpdir package
# ###########################################################################
