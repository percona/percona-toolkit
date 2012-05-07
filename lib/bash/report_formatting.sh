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
# report_formatting package
# ###########################################################################

# Package: report_formatting
# Common report formatting functions for the summary tools.

set -u

POSIXLY_CORRECT=1
export POSIXLY_CORRECT

fuzzy_formula='
   rounded = 0;
   if (fuzzy_var <= 10 ) {
      rounded   = 1;
   }
   factor = 1;
   while ( rounded == 0 ) {
      if ( fuzzy_var <= 50 * factor ) {
         fuzzy_var = sprintf("%.0f", fuzzy_var / (5 * factor)) * 5 * factor;
         rounded   = 1;
      }
      else if ( fuzzy_var <= 100  * factor) {
         fuzzy_var = sprintf("%.0f", fuzzy_var / (10 * factor)) * 10 * factor;
         rounded   = 1;
      }
      else if ( fuzzy_var <= 250  * factor) {
         fuzzy_var = sprintf("%.0f", fuzzy_var / (25 * factor)) * 25 * factor;
         rounded   = 1;
      }
      factor = factor * 10;
   }'

# Does fuzzy rounding: rounds to nearest interval, but the interval gets larger
# as the number gets larger.  This is to make things easier to diff.
fuzz () {
   awk -v fuzzy_var="$1" "BEGIN { ${fuzzy_formula} print fuzzy_var;}"
}

# Fuzzy computes the percent that $1 is of $2
fuzzy_pct () {
   local pct="$(awk -v one="$1" -v two="$2" 'BEGIN{ if (two > 0) { printf "%d", one/two*100; } else {print 0} }')";
   echo "$(fuzz "${pct}")%"
}

# Prints a section header. All spaces in the string passed in are replaced
# with #'s and all underscores with spaces.
section () {
   local str="$1"
   awk -v var="${str} _" 'BEGIN {
      line = sprintf("# %-60s", var);
      i = index(line, "_");
      x = substr(line, i);
      gsub(/[_ \t]/, "#", x);
      printf("%s%s\n", substr(line, 1, i-1), x);
   }'
}

NAME_VAL_LEN=12
name_val () {
   # We use $NAME_VAL_LEN here because the two summary tools, as well as
   # the tests, use diffent widths.
   printf "%+*s | %s\n" "${NAME_VAL_LEN}" "$1" "$2"
}

# Sub: shorten
#   Shorten a value in bytes to another representation.
shorten() {
   local num="$1"
   local prec="${2:-2}"
   local div="${3:-1024}"

   # By default Mebibytes (MiB), Gigibytes (GiB), etc. are used because
   # that's what MySQL uses.  This may create odd output for values like
   # 1500M * 2 (bug 937793) because the base unit is MiB but the code
   # see 1,572,864,000 * 2 = 3,145,728,000 which is > 1 GiB so it uses
   # GiB as the unit, resulting in 2.9G instead of 3.0G that the user
   # might expect to see.  There's no easy way to determine that
   # 3,145,728,000 was actually a multiple of MiB and not some weird GiB
   # value to begin with like 3.145G.  The Perl lib Transformers::shorten()
   # uses MiB, GiB, etc. too.
   echo "$num" | awk -v prec="$prec" -v div="$div" '
      {
         num  = $1;
         unit = num >= 1125899906842624 ? "P" \
              : num >= 1099511627776    ? "T" \
              : num >= 1073741824       ? "G" \
              : num >= 1048576          ? "M" \
              : num >= 1024             ? "k" \
              :                           "";
         while ( num >= div ) {
            num /= div;
         }
         printf "%.*f%s", prec, num, unit;
      }
   '
}

group_concat () {
   sed -e '{H; $!d;}' -e 'x' -e 's/\n[[:space:]]*\([[:digit:]]*\)[[:space:]]*/, \1x/g' -e 's/[[:space:]][[:space:]]*/ /g' -e 's/, //' "${1}"
}

# ###########################################################################
# End report_formatting package
# ###########################################################################
