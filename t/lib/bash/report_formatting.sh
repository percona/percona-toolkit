#!/usr/bin/env bash

plan 20

. "$LIB_DIR/report_formatting.sh"

is                         \
   "$(shorten 10485760 1)" \
   "10.0M"                 \
   "10485760, 1 precision, default divisor => 10.0M"

is                           \
   "$(shorten 3145728000 1)" \
   "2.9G"                 \
   "3145728000, 1 precision, default divisor => 2.9G"

is                                \
   "$(shorten 3145728000 1 1000)" \
   "3.1G"                         \
   "3145728000, 1 precision, divisor 1000 => 3.1G"

is                  \
   "$(shorten 0 0)" \
   "0"                 \
   "0, 0 precision, default divisor => 0"

is                           \
   "$(shorten 1572864000 1)" \
   "1.5G"                 \
   "1572864000, 1 precision, default divisor => 1.5G"

is                           \
   "$(shorten 1572864000 1 1000)" \
   "1.6G"                 \
   "1572864000, 1 precision, divisor 1000 => 1.6G"

is                           \
   "$(shorten 364 0)" \
   "364"                 \
   "364, 0 precision, default divisor => 364"

is                           \
   "$(shorten 364 1)" \
   "364.0"                 \
   "364, 1 precision, default divisor => 364"

is                           \
   "$(shorten 649216 1)" \
   "634.0k"                 \
   "649216, 1 precision, default divisor => 634.0k"

is                           \
   "$(shorten 6492100000006 1)" \
   "5.9T"                 \
   "6492100000006, 1 precision, default divisor => 5.9T"

is                           \
   "$(shorten 6492100000006 1 1000)" \
   "6.5T"                 \
   "6492100000006, 1 precision, divisor 1000 => 6.5T"

is "$(shorten 1059586048 1)" \
   "1010.5M" \
   "1059586048 => 1010.5M (bug 993436)"

# section

is \
   "$(section "A")" \
   "# A ##########################################################" \
   "Sanity check, section works"

is \
   "$(section "A B C")" \
   "# A B C ######################################################" \
   "section doesn't replaces spaces with #s"

is \
   "$(section "A_B_C")" \
   "# A#B#C#######################################################" \
   "replace extra underscores with #s"

# name_val

NAME_VAL_LEN=0

is \
   "$(name_val "A" "B")" \
   "A | B" \
   "name_val and NAME_VAL_LEN work"

# fuzz

is $(fuzz 11) "10" "fuzz 11"
is $(fuzz 49) "50" "fuzz 49"

# fuzzy_pct

is \
   "$( fuzzy_pct  28 64 )" \
   "45%" \
   "fuzzy_pct of 64 and 28 is 45"


is \
   "$( fuzzy_pct  40 400 )" \
   "10%" \
   "fuzzy_pct of 40 and 400 is 10"


# ###########################################################################
# Done
# ###########################################################################
