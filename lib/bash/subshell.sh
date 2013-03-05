# This program is copyright 2013 Percona Ireland Ltd.
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
# subshell package
# ###########################################################################

# Package: subshell

set -u

wait_for_subshells() {
   local max_wait=$1
   if [ "$(jobs)" ]; then
      log "Waiting up to $max_wait seconds for subprocesses to finish..."
      local slept=0
      while [ -n "$(jobs)" ]; do
         local subprocess_still_running=""
         for pid in $(jobs -p); do
            if kill -0 $pid >/dev/null 2>&1; then
               subprocess_still_running=1
            fi
         done
         if [ "$subprocess_still_running" ]; then
            sleep 1
            slept=$((slept + 1))
            [ $slept -ge $max_wait ] && break
         else
            break
         fi
      done
   fi
}

kill_all_subshells() {
   if [ "$(jobs)" ]; then
      for pid in $(jobs -p); do
         if kill -0 $pid >/dev/null 2>&1; then
            # This isn't an warning (we don't want exit status 1) because
            # the system may be running slowly so it's just "natural" that
            # a collector may get stuck or run really slowly.
            log "Killing subprocess $pid"
            kill $pid >/dev/null 2>&1
         fi
      done
   else
      log "All subprocesses have finished"
   fi
}

# ###########################################################################
# End subshell package
# ###########################################################################
