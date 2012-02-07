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
# alt_cmds package
# ###########################################################################

# Package: alt_cmds
# alt_cmds provides alternatives to commands that aren't on all systems.

set -u

# seq N, return 1, ..., 5
_seq() {
   local i="$1"
   awk "BEGIN { for(i=1; i<=$i; i++) print i; }"
}

_pidof() {
   local cmd="$1"
   if ! pidof "$cmd" 2>/dev/null; then
      ps -eo pid,ucomm | awk -v comm="$cmd" '$2 == comm { print $1 }'
   fi
}

_lsof() {
   local pid="$1"
   if ! lsof -p $pid 2>/dev/null; then
      /bin/ls -l /proc/$pid/fd 2>/dev/null
   fi
}

_which() {
   # which on CentOS is aliased to a cmd that prints extra stuff.
   # Also, if the cmd isn't found, a msg is printed to stderr.
   [ -x /usr/bin/which ] && /usr/bin/which "$1" 2>/dev/null | awk '{print $1}'
}

# ###########################################################################
# End alt_cmds package
# ###########################################################################
