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

package Foo::is;
use Lmo qw(is);

has 'stuff' => (is => 'ro');

package main;

my $f = Foo::is->new(stuff => 'foo');
is $f->stuff, 'foo', 'values passed to constructor are successfully accepted';
eval { $f->stuff('barbaz') };
ok $@, 'setting values after initialization throws an exception';

done_testing;
