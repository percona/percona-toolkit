#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use Safeguards;
use Percona::Test;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $sample = "t/lib/samples/bash/";

my $safeguards = Safeguards->new(
   disk_bytes_free => 104857600,
   disk_pct_free   => 10,
);

# Filesystem   1024-blocks     Used Available Capacity  Mounted on
# /dev/disk0s2   118153176 94409664  23487512    81%    /
#
# Those values are in Kb, so:
#   used     = 94409664 (94.4G) = 96_675_495_936 bytes
#   free     = 23487512 (23.4G) = 24_051_212_288 bytes
#   pct free = 100 - 81         = 19 %
my $df = slurp_file("$trunk/$sample/diskspace001.txt");

ok(
   $safeguards->check_disk_space(
      disk_space => $df,
   ),
   "diskspace001: Enough bytes and pct free"
);

$safeguards = Safeguards->new(
   disk_bytes_free => 104857600,
   disk_pct_free   => 20,
);

ok(
   !$safeguards->check_disk_space(
      disk_space => $df,
   ),
   "diskspace001: Not enough pct free"
);

$safeguards = Safeguards->new(
   disk_bytes_free => 24_051_212_289,
   disk_pct_free   => 5,
);

ok(
   !$safeguards->check_disk_space(
      disk_space => $df,
   ),
   "diskspace001: Not enough bytes free"
);

done_testing;
