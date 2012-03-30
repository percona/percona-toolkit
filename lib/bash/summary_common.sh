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
# summary_common package
# ###########################################################################

# Package: summary_common
# Common functions between the summary packages.

set -u

CMD_FILE="$( _which file 2>/dev/null )"
CMD_NM="$( _which nm 2>/dev/null )"
CMD_OBJDUMP="$( _which objdump 2>/dev/null )"

# Tries to find the niceness of the passed in PID. First with ps, and
# failing that, with a bit of C, using getpriority().
# Returns the nice for the pid, or "?" if it can't find any.
get_nice_of_pid () {
   local pid="$1"
   local niceness="$(ps -p $pid -o nice | awk '$1 !~ /[^0-9]/ {print $1; exit}')"

   if [ -n "${niceness}" ]; then
      echo $niceness
   else
      local tmpfile="$TMPDIR/nice_through_c.tmp.c"
      _d "Getting the niceness from ps failed, somehow. We are about to try this:"
      cat <<EOC > "$tmpfile"
#include <sys/time.h>
#include <sys/resource.h>
#include <errno.h>
#include <stdio.h>

int main(void) {
   int priority = getpriority(PRIO_PROCESS, $pid);
   if ( priority == -1 && errno == ESRCH ) {
      return 1;
   }
   else {
      printf("%d\\n", priority);
      return 0;
   }
}

EOC
      local c_comp=$(_which gcc)
      if [ -z "${c_comp}" ]; then
         c_comp=$(_which cc)
      fi
      _d "$tmpfile: $( cat "$tmpfile" )"
      _d "$c_comp -xc \"$tmpfile\" -o \"$tmpfile\" && eval \"$tmpfile\""
      $c_comp -xc "$tmpfile" -o "$tmpfile" 2>/dev/null && eval "$tmpfile" 2>/dev/null
      if [ $? -ne 0 ]; then
         echo "?"
         _d "Failed to get a niceness value for $pid"
      fi
   fi
}

# Fetches the oom value for a given pid.
# To avoi deprecation warnings, tries /proc/PID/oom_score_adj first.
# Will only work if /proc/cpuinfo is available.
get_oom_of_pid () {
   local pid="$1"
   local oom_adj=""

   if [ -n "${pid}" -a -e /proc/cpuinfo ]; then
      if [ -s "/proc/$pid/oom_score_adj" ]; then
         oom_adj=$(cat "/proc/$pid/oom_score_adj" 2>/dev/null)
         _d "For $pid, the oom value is $oom_adj, retreived from oom_score_adj"
      else
         oom_adj=$(cat "/proc/$pid/oom_adj" 2>/dev/null)
         _d "For $pid, the oom value is $oom_adj, retreived from oom_adj"
      fi
   fi

   if [ -n "${oom_adj}" ]; then
      echo "${oom_adj}"
   else
      echo "?"
      _d "Can't find the oom value for $pid"
   fi
}

has_symbols () {
   local executable="$(_which "$1")"
   local has_symbols=""

   if    [ "${CMD_FILE}" ] \
      && [ "$($CMD_FILE "${executable}" | grep 'not stripped' )" ]; then
      has_symbols=1
   elif    [ "${CMD_NM}" ] \
        || [ "${CMD_OBJDMP}" ]; then
      if    [ "${CMD_NM}" ] \
         && [ !"$("${CMD_NM}" -- "${executable}" 2>&1 | grep 'File format not recognized' )" ]; then
         if [ -z "$( $CMD_NM -- "${executable}" 2>&1 | grep ': no symbols' )" ]; then
            has_symbols=1
         fi
      elif [ -z "$("${CMD_OBJDUMP}" -t -- "${executable}" | grep '^no symbols$' )" ]; then
         has_symbols=1
      fi
   fi

   if [ "${has_symbols}" ]; then
      echo "Yes"
   else
      echo "No"
   fi
}

setup_data_dir () {
   local OPT_SAVE_DATA="$1"
   local data_dir=""
   if [ -z "$OPT_SAVE_DATA" ]; then
      # User didn't specify a --save-data dir, so use a sub-dir in our tmpdir.
      mkdir "$TMPDIR/data" || die "Cannot mkdir $TMPDIR/data"
      data_dir="$TMPDIR/data"
   else
      # Check the user's --save-data dir.
      if [ ! -d "$OPT_SAVE_DATA" ]; then
         mkdir "$OPT_SAVE_DATA" || die "Cannot mkdir $OPT_SAVE_DATA"
      elif [ "$( ls "$OPT_SAVE_DATA" | wc -l )" != "0" ]; then
         die "--save-samples directory isn't empty, halting."
      fi
      touch "$OPT_SAVE_DATA/test" || die "Cannot write to $OPT_SAVE_DATA"
      rm "$OPT_SAVE_DATA/test"    || die "Cannot rm $OPT_SAVE_DATA/test"
      data_dir="$OPT_SAVE_DATA"
   fi
   echo "$data_dir"
}

# gets a value from the passed in file.
get_var () {
   local varname="$1"
   local file="$2"
   awk -v pattern="${varname}" '$1 == pattern { if (length($2)) { print substr($0, index($0,$2)) } }' "${file}"
}

# ###########################################################################
# End summary_common package
# ###########################################################################
