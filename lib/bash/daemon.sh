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
# daemon package
# ###########################################################################

# Package: daemon
# daemon handles daemon related tasks like checking a PID file.

set -u

# Sub: make_pid_file
#   Check and make a PID file.
#
# Arguments:
#   file - File to write PID to.
#   pid  - PID to write into file.
make_pid_file() {
   local file="$1"
   local pid="$2"

   # Yes there's a race condition here, between checking if the file exists
   # and creating it, but it's not important enough to handle.

   if [ -f "$file" ]; then
      # PID file already exists.  See if the pid it contains is still running.
      # If yes, then die.  Else, the pid file is stale and we can reclaim it.
      local old_pid=$(cat "$file")
      if [ -z "$old_pid" ]; then
         # PID file is empty, so be safe and die since we can't check a
         # non-existent pid.
         die "PID file $file already exists but it is empty"
      else
         kill -0 $old_pid 2>/dev/null
         if [ $? -eq 0 ]; then
            die "PID file $file already exists and its PID ($old_pid) is running"
         else
            echo "Overwriting PID file $file because its PID ($old_pid)" \
                 "is not running"
         fi
      fi
   fi

   # PID file doesn't exist, or it does but its pid is stale.
   echo "$pid" > "$file"
   if [ $? -ne 0 ]; then
      die "Cannot create or write PID file $file"
   fi
}

remove_pid_file() {
   local file="$1"
   if [ -f "$file" ]; then
      rm "$file"
   fi
}

# ###########################################################################
# End daemon package
# ###########################################################################
