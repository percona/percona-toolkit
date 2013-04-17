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

package Foo::coerce;
use Lmo;

has 'stuff' => (coerce => sub { uc $_[0] });

package main;

my $f = Foo::coerce->new(stuff => 'fubar');
is $f->stuff, 'FUBAR', 'values passed to constructor are successfully coerced';
$f->stuff('barbaz');
is $f->stuff, 'BARBAZ', 'values passed to setters are successfully coerced';


done_testing;
