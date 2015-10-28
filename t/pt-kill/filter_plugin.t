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
use Sandbox;
require "$trunk/bin/pt-kill";

my $sample = "$trunk/t/lib/samples/pl";
my $filter = "$trunk/t/pt-kill/samples";
my @args   = qw(--test-matching);
my $output;

# #############################################################################
# Basic filter 
# #############################################################################

$output = output(
   sub { pt_kill::main(@args, "$sample/recset010.txt",
      '--filter', "$filter/filter002.txt",  
      qw(--match-all),
      qw(--victims all --print)); }
);

ok(
   $output =~ /foo/m && $output !~ /bar/s,
   "basic --filter function works"
);

# #############################################################################
# Done.
# #############################################################################
exit;
