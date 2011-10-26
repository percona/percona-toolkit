# Print usage (--help).
usage() {
   local file=$1

   local usage=$(grep '^Usage: ' $file)
   local opts=$(grep -A 2 '^=item --' $file | sed -e 's/^=item //' -e 's/^\([A-Z]\)/   \1/' -e 's/^--$//' > $TMPDIR/help)

   if [ "${OPT_ERR}" ]; then
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

# Parse command line options.
declare -a ARGV   # non-option args (probably input files)
declare EXT_ARGV  # everything after -- (args for an external command)
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
      eval "$opt"="$default"
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
      val=1
      if [ -n "$required_arg" ]; then
         if [ $# -eq 0 ]; then
            die "--$opt requires a $required_arg argument"
         else
            val="$1"
            shift
         fi
      fi
      opt=$(echo $opt | sed 's/-/_/g' | tr [:lower:] [:upper:])
      eval "$opt"="$val"
   done
}
