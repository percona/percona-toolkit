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

# #############################################################################
# Issue 565: mk-query-digest isn't compiling filter correctly
# #############################################################################
my $output = `$trunk/bin/pt-query-digest --type tcpdump --filter '\$event->{No_index_used} || \$event->{No_good_index_used}' --group-by tables  $trunk/t/lib/samples/tcpdump/tcpdump014.txt 2>&1`;
unlike(
   $output,
   qr/Can't use string/,
   '--filter compiles correctly (issue 565)'
);

# #############################################################################
# Done.
# #############################################################################
exit;
