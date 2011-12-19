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
# tmpdir package
# ###########################################################################

# Package: tmpdir
# tmpdir make a secure temporary directory using mktemp.

set -u

# Global variables.
TMPDIR=""

# Sub: mk_tmpdir
#   Create a secure tmpdir and set TMPDIR.
#
# Optional Arguments:
#   dir - User-specified tmpdir (default none).
#
# Set Global Variables:
#   TMPDIR - Absolute path of secure temp directory.
mk_tmpdir() {
   local dir=${1:-""}

   if [ -n "$dir" ]; then
      if [ ! -d "$dir" ]; then
         mkdir $dir || die "Cannot make tmpdir $dir"
      fi
      TMPDIR="$dir"
   else
      local tool=`basename $0`
      local pid="$$"
      TMPDIR=`mktemp -d /tmp/${tool}.${pid}.XXXXX` \
         || die "Cannot make secure tmpdir"
   fi
}

# Sub: rm_tmpdir
#   Remove the tmpdir and unset TMPDIR.
#
# Optional Global Variables:
#   TMPDIR - TMPDIR set by <mk_tmpdir()>.
#
# Set Global Variables:
#   TMPDIR - Set to "".
rm_tmpdir() {
   if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
      rm -rf $TMPDIR
   fi
   TMPDIR=""
}

# ###########################################################################
# End tmpdir package
# ###########################################################################
