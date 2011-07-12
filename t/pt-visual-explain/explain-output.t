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
require "$trunk/bin/pt-visual-explain";

my $e = new ExplainTree;
my $t;
my $o;

$t = $e->parse( load_file('t/pt-visual-explain/samples/dependent_subquery.sql') );
$o = load_file('t/pt-visual-explain/samples/dependent_subquery.txt');
is_deeply(
   $e->pretty_print($t),
   $o,
   'Output formats correctly',
);


# #############################################################################
# Done.
# #############################################################################
exit;
