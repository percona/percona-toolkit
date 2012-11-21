#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 2;

use PerconaTest;
require "$trunk/bin/pt-variable-advisor";

my $cmd = "$trunk/bin/pt-variable-advisor";
my $output;

$output = `$cmd --source-of-variables=/tmp/foozy-fazzle-bad-file 2>&1`;
like(
   $output,
   qr/--source-of-variables file \S+ does not exist/,
   "--source-of-variables file doesn't exit"
);

$output = `$cmd --source-of-variables mysql 2>&1`;
like(
   $output,
   qr/DSN must be specified/,
   "--source-of-variablels=mysql requires DSN"
);

# #############################################################################
# Done.
# #############################################################################
exit;
