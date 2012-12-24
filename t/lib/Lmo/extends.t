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

use lib "$ENV{PERCONA_TOOLKIT_BRANCH}/t/lib/Lmo";
use Bar;

my $b = Bar->new;

ok $b->isa('Foo'), 'Bar is a subclass of Foo';

is "@Bar::ISA", "Foo", 'Extends with multiple classes not supported';

ok 'Foo'->can('stuff'), 'Foo is loaded';
ok not('Bar'->can('buff')), 'Boo is not loaded';

done_testing;
