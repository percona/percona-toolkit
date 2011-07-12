#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 6;

use MockSth;
use PerconaTest;

my $m;

$m = new MockSth();

is($m->{Active}, 0, 'Empty is not active');
is($m->fetchrow_hashref(), undef, 'Cannot fetch from empty');

$m = new MockSth(
   { a => 1 },
);
ok($m->{Active}, 'Has rows, is active');
is_deeply($m->fetchrow_hashref(), { a => 1 }, 'Got the row');
is($m->{Active}, '', 'Not active after fetching');
is($m->fetchrow_hashref(), undef, 'Cannot fetch from empty');

exit;
