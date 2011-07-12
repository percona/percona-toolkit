#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 9;

use PerconaTest;

my ($output, $output2);
my $cmd = "$trunk/bin/pt-checksum-filter";

$output = `$cmd $trunk/t/pt-table-checksum/samples/sample_1`;
chomp $output;
is($output, '', 'No output from single file');
is($CHILD_ERROR >> 8, 0, 'Exit status is 0');

$output = `$cmd $trunk/t/pt-table-checksum/samples/sample_1 --equal-databases sakila,sakila2`;
chomp $output;
like($output, qr/sakila2.*actor/, 'sakila2.actor is different with --equal-databases');
is($CHILD_ERROR >> 8, 1, 'Exit status is 1');

$output = `$cmd $trunk/t/pt-table-checksum/samples/sample_1 --ignore-databases`;
chomp $output;
like($output, qr/sakila2.*actor/, 'sakila2.actor is different with --ignore-databases');
is($CHILD_ERROR >> 8, 1, 'Exit status is 1');

$output = `$cmd $trunk/t/pt-table-checksum/samples/sample_2 --unique host`;
chomp $output;
is($output, "127.0.0.1\nlocalhost", "Unique hostnames differ");

$output = `$cmd $trunk/t/pt-table-checksum/samples/sample_2 --unique db`;
chomp $output;
is($output, "sakila", "Unique dbs differ");

$output = `$cmd $trunk/t/pt-table-checksum/samples/sample_2 --unique table`;
chomp $output;
is($output, "actor", "Unique tables differ");

exit;
