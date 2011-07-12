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

# #############################################################################
# Issue 687: Test segfaults on old version of Perl
# #############################################################################
my $zcat = `uname` =~ m/Darwin/ ? 'gzcat' : 'zcat';
my $output = `$zcat $trunk/t/lib/samples/slowlogs/slow039.txt.gz | $trunk/bin/pt-query-digest 2>/tmp/mqd-warnings.txt`;
like(
   $output,
   qr/Query 1:/,
   'INSERT that segfaulted fingerprint() (issue 687)'
);

$output = `cat /tmp/mqd-warnings.txt`;
chomp $output;
is(
   $output,
   '',
   'No warnings on INSERT that segfaulted fingerprint() (issue 687)',
);

diag(`rm -rf /tmp/mqd-warnings.txt`);

# #############################################################################
# Done.
# #############################################################################
exit;
