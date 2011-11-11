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
shift @INC;  # our unshift (above)
shift @INC;  # PerconaTest's unshift

require "$trunk/bin/pt-tcp-model";

my @args   = qw();
my $in1    = "$trunk/t/lib/samples/simple-tcpdump/";
my $in2    = "$trunk/t/pt-tcp-model/samples/in/";
my $out    = "t/pt-tcp-model/samples/out/";
my $output = '';

# ############################################################################
# Basic queries that parse without problems.
# ############################################################################
ok(
   no_diff(
      sub { pt_tcp_model::main(@args, "$in1/simpletcp001.txt") },
      "$out/simpletcp001.txt",
   ),
   'Analysis for simpletcp001.txt'
);

ok(
   no_diff(
      sub { pt_tcp_model::main(@args, "$in2/sorted001.txt",
         qw(--type requests --run-time 1)) },
      "$out/sorted001.txt",
   ),
   'Analysis for sorted001.txt (issue 1341)'
);

# #############################################################################
# Done.
# #############################################################################
exit;
