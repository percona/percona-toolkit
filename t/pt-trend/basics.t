#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 1;

use PerconaTest;
require "$trunk/bin/pt-trend";


my $in   = "$trunk/t/lib/samples/slowlogs";
my $out  = "t/pt-trend/samples/";
my @args = ();

$ENV{TZ}='MST7MDT';

ok(
   no_diff(
      sub { pt_trend::main(@args, "$in/slow053.txt") },
      "$out/slow053.txt",
   ),
   "Analysis for slow053.txt"
);

# #############################################################################
# Done.
# #############################################################################
exit;
