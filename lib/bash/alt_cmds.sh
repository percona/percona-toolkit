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


# We don't get things like "which: command not found", so for the pathological
# case where /usr/bin/which isn't installed, we check that "which which" and
# if which really isn't there then just return the command passed in and hope
# they are somewhere

# TODO:
#  we just need to redirect STDERR when we execute 
#  "which" and check it. Some shells are really weird this way. We 
#  can't check "which"'s exit status because it will be nonzero if 
#  the sought-for command doesn't exist.
# 
_which() {
   # which on CentOS is aliased to a cmd that prints extra stuff.
   # Also, if the cmd isn't found, a msg is printed to stderr.
   if [ -x /usr/bin/which ]; then
      /usr/bin/which "$1" 2>/dev/null | awk '{print $1}'
   elif which which 1>/dev/null 2>&1; then
      # Well, this is bizarre. /usr/bin/which either doesn't exist or
      # isn't executable, but the shell can use which just fine.
      # So we bite the bullet, hope that it doesn't do anything
      # insane, and use it.
      which "$1" 2>/dev/null | awk '{print $1}'
   else
      # We don't have which. Just return the command that was
      # originally passed in.
      echo "$1"
   fi
}

# ###########################################################################
# End alt_cmds package
# ###########################################################################
