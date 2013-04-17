#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;
use PerconaTest;

require "$trunk/bin/pt-online-schema-change";

my $q  = Quoter->new;
my $tp = TableParser->new(Quoter => $q);

sub test_func {
   my ($alter, $renamed_cols) = @_;
   die "No alter arg" unless $alter;
   die "No renamed_cols arg" unless $renamed_cols;
   (my $show_alter = $alter) =~ s/\n/\\n/g;
   
   my $got_renamed_cols = eval {
      pt_online_schema_change::find_renamed_cols(
         alter       => $alter,
         TableParser => $tp,
      );
   };
   if ( $EVAL_ERROR ) {
      is_deeply(
         undef,
         $renamed_cols,
         $show_alter,
      ) or diag($EVAL_ERROR);
   }
   else {
      is_deeply(
         $got_renamed_cols,
         $renamed_cols,
         $show_alter,
      ) or diag(Dumper($got_renamed_cols));
   }
}

# #############################################################################
# Single column alters
# #############################################################################

test_func(
   "change old_column_name new_column_name varchar(255) NULL",
   {
      old_column_name => 'new_column_name',
   },
);

# Case-sensitive?
test_func(
   "CHANGE old_column_name new_column_name VARCHAR(255) NULL",
   {
      old_column_name => 'new_column_name',
   },
);

# Optional COLUMN?
test_func(
   "CHANGE column old_column_name new_column_name VARCHAR(255) NULL",
   {
      old_column_name => 'new_column_name',
   },
);

# Space-sensitive?
test_func(
   "CHANGE   a       z     VARCHAR(255)  NULL",
   {
      a => 'z',
   },
);

# Backtick-sensitive?
test_func(
   "CHANGE `a` `z` VARCHAR(255)  NULL",
   {
      a => 'z',
   },
);

# Column named column?
test_func(
   "CHANGE `column` new_column_name VARCHAR(255) NULL",
   {
      column => 'new_column_name',
   },
);


# Extended ascii?
test_func(
   "CHANGE `café` `tête-à-tête` INT",
   {
      'café' => 'tête-à-tête',
   },
);

# UTF-8?
if( Test::Builder->VERSION < 2 ) {
   foreach my $method ( qw(output failure_output) ) {
      binmode Test::More->builder->$method(), ':encoding(UTF-8)';
   }
}
test_func(
   "CHANGE `\x{30cb}` `\x{30cd}` INT",
   {
      "\x{30cb}" => "\x{30cd}",
   },
);
# Mixed backtick-sensitive?
test_func(
   "CHANGE `a` z VARCHAR(255)  NULL",
   {
      a => 'z',
   },
);

test_func(
   "CHANGE a `z` VARCHAR(255)  NULL",
   {
      a => 'z',
   },
);

# Ansi quotes-sensitive? (should matter)
test_func(
   qq{CHANGE "a" "z" VARCHAR(255)  NULL},
   {
      a => 'z',
   },
);

# Embedded backticks?
test_func(
   "CHANGE `a``a` z VARCHAR(255)  NULL",
   {
      'a`a' => 'z',
   },
);

# Emebedded spaces?
test_func(
   "CHANGE `a yes  ` z VARCHAR(255)  NULL",
   {
      'a yes  ' => 'z',
   },
);

test_func(
   "CHANGE `  yes  ` `\nyes!\na` VARCHAR(255)  NULL",
   {
      '  yes  ' => "\nyes!\na",
   },
);

test_func(
   "CHANGE `  yes  ` `\nyes!\na` VARCHAR(255)  NULL",
   {
      '  yes  ' => "\nyes!\na",
   },
);

# #############################################################################
# Two column alters
# #############################################################################

test_func(
   "CHANGE a z VARCHAR(255)  NULL, CHANGE foo bar INT",
   {
      a   => 'z',
      foo => 'bar',
   },
);

# Pathological
test_func(
   "CHANGE a `CHANGE a z VARCHAR(255) NOT NULL` VARCHAR(255)  NULL, CHANGE foo bar INT",
   {
      a   => 'CHANGE a z VARCHAR(255) NOT NULL',
      foo => 'bar',
   },
);


# #############################################################################
# Fake alters
# #############################################################################

# Not really renamed.
test_func(
   "CHANGE foo foo FLOAT",
   {
   },
);

# Not really renamed, should ignore case
test_func(
   "CHANGE foo FOO FLOAT",
   {
   },
);

# TODO
## Not really an alter, pathological
#test_func(
#   "MODIFY `CHANGE a z VARCHAR(255) NOT NULL` FLOAT",
#   {
#   },
#);

# #############################################################################
# Done.
# #############################################################################
done_testing;
