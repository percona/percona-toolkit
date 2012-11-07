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

   my %got_renamed_cols = eval {
      pt_online_schema_change::find_renamed_cols($alter, $tp);
   };
   if ( $EVAL_ERROR ) {
      is_deeply(
         undef,
         $renamed_cols,
         $alter,
      ) or diag($EVAL_ERROR);
   }
   else {
      is_deeply(
         \%got_renamed_cols,
         $renamed_cols,
         $alter,
      ) or diag(Dumper(\%got_renamed_cols));
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

# Extended ascii?
test_func(
   "CHANGE `café` `tête-à-tête` INT",
   {
      'café' => 'tête-à-tête',
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

# #############################################################################
# Fake alters
# #############################################################################

# Not really renamed.
test_func(
   "CHANGE foo foo FLOAT",
   {
   },
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
