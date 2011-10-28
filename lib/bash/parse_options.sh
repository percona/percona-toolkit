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
# parse_options package
# ###########################################################################

# Package: parse_options
# parse_options parses Perl POD options from Bash tools and creates
# global variables for each option.

set -u

# Global variables.  These must be global because declare inside a
# sub will be scoped locally.
declare -a ARGV   # non-option args (probably input files)
declare EXT_ARGV  # everything after -- (args for an external command)

# Sub: usage
#   Print usage (--help) and list the program's options.
#
# Arguments:
#   file - Program file with Perl POD which has usage and options.
#
# Required Global Variables:
#   TIMDIR  - Temp directory set by <set_TMPDIR()>.
#   TOOL    - Tool's name.
#
# Optional Global Variables:
#   OPT_ERR - Command line option error message.
usage() {
   local file=$1

   local usage=$(grep '^Usage: ' $file)
   local opts=$(grep -A 2 '^=item --' $file | sed -e 's/^=item //' -e 's/^\([A-Z]\)/   \1/' -e 's/^--$//' > $TMPDIR/help)

   if [ "$OPT_ERR" ]; then
      echo "Error: ${OPT_ERR}" >&2
   fi
   echo $usage >&2
   echo >&2
   echo "Options:" >&2
   echo >&2
   cat $TMPDIR/help >&2
   echo >&2
   echo "For more information, 'man $TOOL' or 'perldoc $file'." >&2
}

# Sub: parse_options
#   Parse Perl POD options from a program file.
#
# Arguments:
#   file - Program file with Perl POD options.
#
# Required Global Variables:
#   TIMDIR  - Temp directory set by <set_TMPDIR()>.
#
# Set Global Variables:
#   This sub decalres a global var for each option by uppercasing the
#   option, removing the option's leading --, changing all - to _, and
#   prefixing with "OPT_".  E.g. --foo-bar becomes OPT_FOO_BAR.
parse_options() {
   local file=$1
   shift

   local opt=""
   local val=""
   local default=""
   local version=""
   local i=0

   awk '
      /^=head1 OPTIONS/ {
         getline
         while ($0 !~ /^=head1/) {
            if ($0 ~ /^=item --.*/) {
               long_opt=substr($2, 3, length($2) - 2)
               short_opt=""
               required_arg=""

               if ($3) {
                  if ($3 ~ /-[a-z]/)
                     short_opt=substr($3, 3, length($3) - 3)
                  else
                     required_arg=$3
               }

               if ($4 ~ /[A-Z]/)
                  required_arg=$4

               getline # blank line
               getline # short description line

               if ($0 ~ /default: /) {
                  i=index($0, "default: ")
                  default=substr($0, i + 9, length($0) - (i + 9))
               }
               else
                  default=""

               print long_opt "," short_opt "," required_arg "," default
            }
            getline
         }
         exit
      }' $file > $TMPDIR/options

   while read spec; do
      opt=$(echo $spec | cut -d',' -f1 | sed 's/-/_/g' | tr [:lower:] [:upper:])
      default=$(echo $spec | cut -d',' -f4)
      eval "OPT_${opt}"="$default"
   done < <(cat $TMPDIR/options)

   for opt; do
      if [ $# -eq 0 ]; then
         break
      fi
      opt=$1
      if [ "$opt" = "--" ]; then
         shift
         EXT_ARGV="$@"
         break
      fi
      if [ "$opt" = "--version" ]; then
         version=$(grep '^pt-[^ ]\+ [0-9]' $0)
         echo "$version"
         exit 0
      fi
      if [ "$opt" = "--help" ]; then
         usage $file
         exit 0
      fi
      shift
      if [ $(expr "$opt" : "-") -eq 0 ]; then
         ARGV[i]="$opt"
         i=$((i+1))
         continue
      fi
      opt=$(echo $opt | sed 's/^-*//')
      spec=$(grep -E "^$opt,|,$opt," "$TMPDIR/options")
      if [ -z "$spec"  ]; then
         die "Unknown option: $opt"
      fi
      opt=$(echo $spec | cut -d',' -f1)
      required_arg=$(echo $spec | cut -d',' -f3)
      val="yes"
      if [ -n "$required_arg" ]; then
         if [ $# -eq 0 ]; then
            die "--$opt requires a $required_arg argument"
         else
            val="$1"
            shift
         fi
      fi
      opt=$(echo $opt | sed 's/-/_/g' | tr [:lower:] [:upper:])
      eval "OPT_${opt}"="$val"
   done
}

# ###########################################################################
# End parse_options package
# ###########################################################################
