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
# parse_options package
# ###########################################################################

# Package: parse_options
# parse_options parses Perl POD options from Bash tools and creates
# global variables for each option.

# XXX
# GLOBAL $TMPDIR AND $TOOL MUST BE SET BEFORE USING THIS LIB!
# XXX

# Parsing command line options with Bash is easy until we have to dealt
# with values that have spaces, e.g. --option="hello world".  This is
# further complicated by command line vs. config file.  From the command
# line, <--option "hello world"> is put into $@ as "--option", "hello world",
# i.e. 2 args.  From a config file, <option=hello world> is either 2 args
# split on the space, or 1 arg as a whole line.  It needs to be 2 args
# split on the = but this isn't possible; see the note before while read
# in _parse_config_files().  Perl tool config files do not work when the
# value is quoted, so we can't quote it either.  And in any case, that
# wouldn't work because then the value would include the literal quotes
# because it's a line from a file, not a command line where Bash will
# interpret the quotes and return a single value in the code. So...

# XXX
# BE CAREFUL MAKING CHANGES TO THIS LIB AND MAKE SURE
# t/lib/bash/parse_options.sh STILL PASSES!
# XXX

set -u

# Global variables.  These must be global because declare inside a
# sub will be scoped locally.
ARGV=""           # Non-option args (probably input files)
EXT_ARGV=""       # Everything after -- (args for an external command)
HAVE_EXT_ARGV=""  # Got --, everything else is put into EXT_ARGV
OPT_ERRS=0        # How many command line option errors
OPT_VERSION=""    # If --version was specified
OPT_HELP=""       # If --help was specified
PO_DIR="$TMPDIR/po"  # Directory with program option spec files

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
   local file="$1"

   local usage=$(grep '^Usage: ' "$file")
   echo $usage
   echo
   echo "For more information, 'man $TOOL' or 'perldoc $file'."
}

usage_or_errors() {
   local file="$1"

   if [ "$OPT_VERSION" ]; then
      local version=$(grep '^pt-[^ ]\+ [0-9]' "$file")
      echo "$version"
      return 1
   fi

   if [ "$OPT_HELP" ]; then
      usage "$file"
      echo
      echo "Command line options:"
      echo
      for opt in $(ls $TMPDIR/po/); do
         local desc=$(cat $TMPDIR/po/$opt | grep '^desc:' | sed -e 's/^desc://')
         echo "--$opt"
         echo "  $desc"
         echo
      done
      return 1
   fi

   if [ $OPT_ERRS -gt 0 ]; then
      echo
      usage "$file"
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
   local file="$1"
   shift

   # XXX
   # Reset all globals else t/lib/bash/parse_options.sh will fail.
   # XXX
   ARGV=""
   EXT_ARGV=""
   HAVE_EXT_ARGV=""
   OPT_ERRS=0
   OPT_VERSION=""
   OPT_HELP=""
   PO_DIR="$TMPDIR/po"

   # Ready the directory for the program option (po) spec files.
   if [ ! -d "$PO_DIR" ]; then
      mkdir "$PO_DIR"
      if [ $? -ne 0 ]; then
         echo "Cannot mkdir $PO_DIR" >&2
         exit 1
      fi
   fi

   rm -rf "$PO_DIR"/*
   if [ $? -ne 0 ]; then
      echo "Cannot rm -rf $PO_DIR/*" >&2
      exit 1
   fi

   _parse_pod "$file"  # Parse POD into program option (po) spec files
   _eval_po            # Eval po into existence with default values

   # If the first option is --config FILES, then remove it and use
   # those files instead of the default config files.
   if [ $# -ge 2 ] &&  [ "$1" = "--config" ]; then
      shift  # --config
      local user_config_files="$1"
      shift  # that ^
      local old_ifs="$IFS"
      IFS=","
      for user_config_file in $user_config_files; do
         _parse_config_files "$user_config_file"
      done
      IFS="$old_ifs"
   else
      _parse_config_files "/etc/percona-toolkit/percona-toolkit.conf" "/etc/percona-toolkit/$TOOL.conf" "$HOME/.percona-toolkit.conf" "$HOME/.$TOOL.conf"
   fi

   # Finally, parse the command line.
   _parse_command_line "$@"
}

_parse_pod() {
   local file="$1"

   # Parse the program options (po) from the POD.  Each option has
   # a spec file like:
   #   $ cat po/string-opt2 
   #   long=string-opt2
   #   type=string
   #   default=foo
   # That's the spec for --string-opt2.  Each line is a key:value pair
   # from the option's POD line like "type: string; default: foo".
   cat "$file" | PO_DIR="$PO_DIR" perl -ne '
      BEGIN { $/ = ""; }
      next unless $_ =~ m/^=head1 OPTIONS/;
      while ( defined(my $para = <>) ) {
         last if $para =~ m/^=head1/;
         chomp;
         if ( $para =~ m/^=item --(\S+)/ ) {
            my $opt  = $1;
            my $file = "$ENV{PO_DIR}/$opt";
            open my $opt_fh, ">", $file or die "Cannot open $file: $!";
            print $opt_fh "long:$opt\n";
            $para = <>;
            chomp;
            if ( $para =~ m/^[a-z ]+:/ ) {
               map {
                  chomp;
                  my ($attrib, $val) = split(/: /, $_);
                  print $opt_fh "$attrib:$val\n";
               } split(/; /, $para);
               $para = <>;
               chomp;
            }
            my ($desc) = $para =~ m/^([^?.]+)/;
            print $opt_fh "desc:$desc.\n";
            close $opt_fh;
         }
      }
      last;
   '
}

_eval_po() {
   # Evaluate the program options into existence as global variables
   # transformed like --my-op == $OPT_MY_OP.  If an option has a default
   # value, it's assigned that value.  Else, it's value is an empty string.
   for opt_spec in $(ls "$PO_DIR"); do
      local opt=""
      local default_val=""
      local neg=0
      while read line; do
         local key=$(echo $line | cut -d ':' -f 1)
         local val=$(echo $line | cut -d ':' -f 2)
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
               echo "Invalid attribute in $PO_DIR/$opt_spec: $line" >&2
               exit 1
         esac 
      done < "$PO_DIR/$opt_spec"

      if [ -z "$opt" ]; then
         echo "No long attribute in option spec $PO_DIR/$opt_spec" >&2
         exit 1
      fi

      if [ $neg -eq 1 ]; then
         if [ -z "$default_val" ] || [ "$default_val" != "yes" ]; then
            echo "Option $opt_spec is negatable but not default: yes" >&2
            exit 1
         fi
      fi

      # Eval the option into existence as a global variable.
      eval "OPT_${opt}"="$default_val"
   done
}

_parse_config_files() {

   for config_file in "$@"; do
      # Next config file if this one doesn't exist.
      test -f "$config_file" || continue

      # We must use while read because values can contain spaces.
      # Else, if we for $(grep ...) then a line like "op=hello world"
      # will return 2 values: "op=hello" and "world".  If we quote
      # the command like for "$(grep ...)" then the entire config
      # file is returned as 1 value like "opt=hello world\nop2=42".
      while read config_opt; do

         # Skip the line if it begins with a # or is blank.
         echo "$config_opt" | grep '^[ ]*[^#]' >/dev/null 2>&1 || continue

         # Strip leading and trailing spaces, and spaces around the first =,
         # and end-of-line # comments.
         config_opt="$(echo "$config_opt" | sed -e 's/^[ ]*//' -e 's/[ ]*\$//' -e 's/[ ]*=[ ]*/=/' -e 's/[ ]*#.*$//')"

         # Skip blank lines.
         [ "$config_opt" = "" ] && continue

         # Options in a config file are not prefixed with --,
         # but command line options are, so one or the other has
         # to add or remove the -- prefix.  We add it for config
         # files rather than trying to strip it from command line
         # options because it's a simpler operation here.
         if ! [ "$HAVE_EXT_ARGV" ]; then
            config_opt="--$config_opt"
         fi

         _parse_command_line "$config_opt"

      done < "$config_file"

      HAVE_EXT_ARGV=""  # reset for each file

   done
}

_parse_command_line() {
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
   local opt=""
   local val=""
   local next_opt_is_val=""
   local opt_is_ok=""
   local opt_is_negated=""
   local real_opt=""
   local required_arg=""

   for opt in "$@"; do
      if [ "$opt" = "--" -o "$opt" = "----" ]; then
         HAVE_EXT_ARGV=1
         continue
      fi
      if [ "$HAVE_EXT_ARGV" ]; then
         # Previous line was -- so this and subsequent options are
         # really external argvs.
         if [ "$EXT_ARGV" ]; then
            EXT_ARGV="$EXT_ARGV $opt"
         else
            EXT_ARGV="$opt"
         fi
         continue
      fi

      if [ "$next_opt_is_val" ]; then
         next_opt_is_val=""
         if [ $# -eq 0 ] || [ $(expr "$opt" : "-") -eq 1 ]; then
            OPT_ERRS=$(($OPT_ERRS + 1))
            echo "$real_opt requires a $required_arg argument" >&2
            continue
         fi
         val="$opt"
         opt_is_ok=1
      else
         # If option does not begin with a hyphen (-), it's a filename, etc.
         if [ $(expr "$opt" : "-") -eq 0 ]; then
            if [ -z "$ARGV" ]; then
               ARGV="$opt"
            else
               ARGV="$ARGV $opt"
            fi
            continue
         fi

         # Save real opt from cmd line for error messages.
         real_opt="$opt"

         # Strip leading -- or --no- from option.
         if $(echo $opt | grep -q '^--no-'); then
            opt_is_negated=1
            opt=$(echo $opt | sed 's/^--no-//')
         else
            opt_is_negated=""
            opt=$(echo $opt | sed 's/^-*//')
         fi

         # Split opt=val pair.
         if $(echo $opt | grep '^[a-z-][a-z-]*=' >/dev/null 2>&1); then
            val="$(echo $opt | awk -F= '{print $2}')"
            opt="$(echo $opt | awk -F= '{print $1}')"
         fi

         # Find the option's spec file.
         if [ -f "$TMPDIR/po/$opt" ]; then
            spec="$TMPDIR/po/$opt"
         else
            spec=$(grep "^short form:-$opt\$" "$TMPDIR"/po/* | cut -d ':' -f 1)
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
         required_arg=$(cat "$spec" | awk -F: '/^type:/{print $2}')
         if [ "$required_arg" ]; then
            # Option takes a value.
            if [ "$val" ]; then
               opt_is_ok=1
            else
               next_opt_is_val=1
            fi
         else
            # Option does not take a value.
            if [ "$val" ]; then
               OPT_ERRS=$(($OPT_ERRS + 1))
               echo "Option $real_opt does not take a value" >&2
               continue
            fi 
            if [ "$opt_is_negated" ]; then
               val=""
            else
               val="yes"
            fi
            opt_is_ok=1
         fi
      fi

      if [ "$opt_is_ok" ]; then
         # Get and transform the opt's long form.  E.g.: -q == --quiet == QUIET.
         opt=$(cat "$spec" | grep '^long:' | cut -d':' -f2 | sed 's/-/_/g' | tr [:lower:] [:upper:])

         # Re-eval the option to update its global variable value.
         eval "OPT_$opt"="'$val'"

         opt=""
         val=""
         next_opt_is_val=""
         opt_is_ok=""
         opt_is_negated=""
         real_opt=""
         required_arg=""
      fi
   done
}

# ###########################################################################
# End parse_options package
# ###########################################################################
