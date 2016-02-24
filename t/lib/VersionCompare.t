#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests=>14;

use VersionCompare;
use PerconaTest;

my @versions      = qw( 5.7         5.6      1
                        5.6         5.7      -1
                        5.6         5.6      0
                        5.17        5.6      1
                        5.9         5.17     -1
                        5.10        5.10     0
                        5.1.2       5.5      -1
                        5           3        1
                        5.6         5.5.5    1
                        5.7.7       5.7.7    0
                        5.6         5.6.0    -1
                        v5.4.3-0    5.7      -1
                        5.7         v5.4.3-0  1
                        v5.7.3-0    v5.4.3-0  1
                       );

while ( @versions ) {
   my $v1  = shift @versions; 
   my $v2  = shift @versions; 
   my $res = shift @versions; 

   ok ( VersionCompare::cmp($v1, $v2) == $res,
        "$v1 vs $v2"
      ) or diag("result was [",VersionCompare::cmp($v1, $v2),"]");
}


# #############################################################################
# Done.
# #############################################################################
#ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
