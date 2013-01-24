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
# log_warn_die package
# ###########################################################################

# Package: log_warn_die
# log_warn_die provides standard log(), warn(), and die() subs.

set -u

# Global variables.
PTFUNCNAME=""
PTDEBUG="${PTDEBUG:-""}"
EXIT_STATUS=0

ts() {
   TS=$(date +%F-%T | tr ':-' '_')
   echo "$TS $*"
}

info() {
   [ ${OPT_VERBOSE:-3} -ge 3 ] && ts "$*"
}

log() {
   [ ${OPT_VERBOSE:-3} -ge 2 ] && ts "$*"
}

warn() {
   [ ${OPT_VERBOSE:-3} -ge 1 ] && ts "$*" >&2
   EXIT_STATUS=1
}

die() {
   ts "$*" >&2
   EXIT_STATUS=1
   exit 1
}

_d () {
   [ "$PTDEBUG" ] && echo "# $PTFUNCNAME: $(ts "$*")" >&2
}

# ###########################################################################
# End log_warn_die package
# ###########################################################################
