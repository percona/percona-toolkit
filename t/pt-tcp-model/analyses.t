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

use MaatkitTest;
shift @INC;  # our unshift (above)
shift @INC;  # MaatkitTest's unshift

require "$trunk/bin/pt-tcp-model";

my @args   = qw();
my $in     = "$trunk/t/lib/samples/simple-tcpdump/";
my $out    = "t/pt-tcp-model/samples/out/";
my $output = '';

# ############################################################################
# Basic queries that parse without problems.
# ############################################################################
ok(
   no_diff(
      sub { pt_tcp_model::main(@args, "$in/simpletcp001.txt") },
      "$out/simpletcp001.txt",
   ),
   'Analysis for simpletcp001.txt'
);

# #############################################################################
# Done.
# #############################################################################
exit;
