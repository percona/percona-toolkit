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
ARGV=""           # Non-option args (probably input files)
EXT_ARGV=""       # Everything after -- (args for an external command)
OPT_ERRS=0        # How many command line option errors
OPT_VERSION="no"  # If --version was specified
OPT_HELP="no"     # If --help was specified

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
   echo $usage >&2
   echo >&2
   echo "For more information, 'man $TOOL' or 'perldoc $file'." >&2
}

usage_or_errors() {
   local file=$1

   if [ "$OPT_VERSION" = "yes" ]; then
      local version=$(grep '^pt-[^ ]\+ [0-9]' $file)
      echo "$version"
      return 1
   fi

   if [ "$OPT_HELP" = "yes" ]; then
      usage "$file"
      echo >&2
      echo "Command line options:" >&2
      echo >&2
      for opt in $(ls $TMPDIR/po/); do
         local desc=$(cat $TMPDIR/po/$opt | grep '^desc:' | sed -e 's/^desc://')
         echo "--$opt" >&2
         echo "  $desc" >&2
         echo >&2
      done
      return 1
   fi

   if [ $OPT_ERRS -gt 0 ]; then
      echo >&2
      usage $file
      return 1
   fi

   # No --help, --version, or errors.
   return 0
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

   # Parse the program options (po) from the POD.  Each option has
   # a spec file like:
   #   $ cat po/string-opt2 
   #   long=string-opt2
   #   type=string
   #   default=foo
   # That's the spec for --string-opt2.  Each line is a key:value pair
   # from the option's POD line like "type: string; default: foo".
   mkdir $TMPDIR/po/ 2>/dev/null
   rm -rf $TMPDIR/po/*
   (
      export PO_DIR="$TMPDIR/po"
      cat $file | perl -ne '
         BEGIN { $/ = ""; }
         next unless $_ =~ m/^=head1 OPTIONS/;
         while ( defined(my $para = <>) ) {
            last if $para =~ m/^=head1/;
            chomp;
            if ( $para =~ m/^=item --(\S+)/ ) {
               my $opt  = $1;
               my $file = "$ENV{PO_DIR}/$opt";
               open my $opt_fh, ">", $file or die "Cannot open $file: $!";
               printf $opt_fh "long:$opt\n";
               $para = <>;
               chomp;
               if ( $para =~ m/^[a-z ]+:/ ) {
                  map {
                     chomp;
                     my ($attrib, $val) = split(/: /, $_);
                     printf $opt_fh "$attrib:$val\n";
                  } split(/; /, $para);
                  $para = <>;
                  chomp;
               }
               my ($desc) = $para =~ m/^([^.]+)/;
               printf $opt_fh "desc:$desc.\n";
               close $opt_fh;
            }
         }
         last;
      '
   )

   # Evaluate the program options into existence as global variables
   # transformed like --my-op == $OPT_MY_OP.  If an option has a default
   # value, it's assigned that value.  Else, it's value is an empty string.
   for opt_spec in $(ls $TMPDIR/po/); do
      local opt=""
      local default_val=""
      local neg=0
      while read line; do
         local key=`echo $line | cut -d ':' -f 1`
         local val=`echo $line | cut -d ':' -f 2`
         case "$key" in
            long)
               opt=$(echo $val | sed 's/-/_/g' | tr [:lower:] [:upper:])
               ;;
            default)
               default_val="$val"
               ;;
            "short form")
               ;;
            type)
               ;;
            desc)
               ;;
            negatable)
               if [ "$val" = "yes" ]; then
                  neg=1
               fi
               ;;
            *)
               echo "Invalid attribute in $TMPDIR/po/$opt_spec: $line" >&2
               exit 1
         esac 
      done < $TMPDIR/po/$opt_spec

      if [ -z "$opt" ]; then
         echo "No long attribute in option spec $TMPDIR/po/$opt_spec" >&2
         exit 1
      fi

      if [ $neg -eq 1 ]; then
         if [ -z "$default_val" ] || [ "$default_val" != "yes" ]; then
            echo "Option $opt_spec is negatable but not default: yes" >&2
            exit 1
         fi
      fi

      eval "OPT_${opt}"="$default_val"
   done

   # Parse the command line options.  Anything after -- is put into
   # EXT_ARGV.  Options must begin with one or two hyphens (--help or -h),
   # else the item is put into ARGV (it's probably a filename, directory,
   # etc.)  The program option specs parsed above are used to valid the
   # command line options.  All options have already been eval'd into
   # existence, but we re-eval opts specified on the command line to update
   # the corresponding global variable's value.  For example, if --foo has
   # a default value 100, then $OPT_FOO=100 already, but if --foo=500 is
   # specified on the command line, then we re-eval $OPT_FOO=500 to update
   # $OPT_FOO.
   for opt; do
      if [ $# -eq 0 ]; then
         break  # no more opts
      fi
      opt=$1
      if [ "$opt" = "--" ]; then
         shift
         EXT_ARGV="$@"
         break
      fi
      shift 
      if [ $(expr "$opt" : "-") -eq 0 ]; then
         # Option does not begin with a hyphen (-), so treat it as
         # a filename, directory, etc.
         if [ -z "$ARGV" ]; then
            ARGV="$opt"
         else
            ARGV="$ARGV $opt"
         fi
         continue
      fi

      # Save real opt from cmd line for error messages.
      local real_opt="$opt"

      # Strip leading -- or --no- from option.
      if $(echo $opt | grep -q '^--no-'); then
         neg=1
         opt=$(echo $opt | sed 's/^--no-//')
      else
         neg=0
         opt=$(echo $opt | sed 's/^-*//')
      fi

      # Find the option's spec file.
      if [ -f "$TMPDIR/po/$opt" ]; then
         spec="$TMPDIR/po/$opt"
      else
         spec=$(grep "^short form:-$opt\$" $TMPDIR/po/* | cut -d ':' -f 1)
         if [ -z "$spec"  ]; then
            OPT_ERRS=$(($OPT_ERRS + 1))
            echo "Unknown option: $real_opt" >&2
            continue
         fi
      fi

      # Get the value specified for the option, if any.  If the opt's spec
      # says it has a type, then it requires a value and that value should
      # be the next item ($1).  Else, typeless options (like --version) are
      # either "yes" if specified, else "no" if negatable and --no-opt.
      required_arg=$(cat $spec | grep '^type:' | cut -d':' -f2)
      if [ -n "$required_arg" ]; then
         if [ $# -eq 0 ]; then
            OPT_ERRS=$(($OPT_ERRS + 1))
            echo "$real_opt requires a $required_arg argument" >&2
            continue
         else
            val="$1"
            shift
         fi
      else
         if [ $neg -eq 0 ]; then
            val="yes"
         else
            val="no"
         fi
      fi

      # Get and transform the opt's long form.  E.g.: -q == --quiet == QUIET.
      opt=$(cat $spec | grep '^long:' | cut -d':' -f2 | sed 's/-/_/g' | tr [:lower:] [:upper:])

      # Re-eval the option to update its global variable value.
      eval "OPT_$opt"="$val"
   done
}

# ###########################################################################
# End parse_options package
# ###########################################################################
