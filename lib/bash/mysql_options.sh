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
# mysql_options package
# ###########################################################################

# Package: mysql_options
# Handle --defaults-file & related options

set -u

mysql_options() {
   local MYSQL_ARGS=""
   if [ -n "$OPT_DEFAULTS_FILE" ]; then
      MYSQL_ARGS="--defaults-file=$OPT_DEFAULTS_FILE"
   fi
   if [ -n "$OPT_PORT" ]; then
      MYSQL_ARGS="$MYSQL_ARGS --port=$OPT_PORT"
   fi
   if [ -n "$OPT_SOCKET" ]; then
      MYSQL_ARGS="$MYSQL_ARGS --socket=$OPT_SOCKET"
   fi
   if [ -n "$OPT_HOST" ]; then
      MYSQL_ARGS="$MYSQL_ARGS --host=$OPT_HOST"
   fi
   if [ -n "$OPT_USER" ]; then
      MYSQL_ARGS="$MYSQL_ARGS --user=$OPT_USER"
   fi
   if [ -n "$OPT_PASSWORD" ]; then
      MYSQL_ARGS="$MYSQL_ARGS --password=$OPT_PASSWORD"
   fi
   
   echo $MYSQL_ARGS
}

# This basically makes sure that --defaults-file comes first
arrange_mysql_options() {
   local opts="$1"
   
   local rearranged=""
   for opt in $opts; do
      if [ "$(echo $opt | awk -F= '{print $1}')" = "--defaults-file" ]; then
          rearranged="$opt $rearranged"
      else
         rearranged="$rearranged $opt"
      fi
   done
   
   echo "$rearranged"
}

# ###########################################################################
# End mysql_options package
# ###########################################################################
