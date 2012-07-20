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

$main::count = 0;

{
   package Nothing;
   use Mo;
   has nothing_special => ( is => 'rw' );
}
ok(Nothing->can("BUILDARGS"), "Every class automatically gets buildargs");

package Foo;
use Mo;
has 'foo' => (is => 'rw');
sub BUILDARGS {
    my $class = shift;
    $main::count++;
    $class->SUPER::BUILDARGS(@_);
}

package Bar;
use Mo;
extends 'Foo';
has 'bar' => (is => 'rw');

package Baz;
use Mo;
extends 'Bar';
has 'baz' => (is => 'rw');
sub BUILDARGS {
    my $class = shift;
    $main::count++;
    $class->SUPER::BUILDARGS(@_)
}

package Gorch;
use Mo;
extends 'Baz';
has 'gorch' => (is => 'rw');

package main;

$main::count = 0;
my $g = Foo->new;
is $main::count, 1, "A class with no explicit parent inherits SUPER::BUILDARGS from Mo::Object";

$main::count = 0;
$g = Gorch->new;
is $main::count, 2, "As does one with a parent that defines it's own BUILDARGS";

done_testing;
