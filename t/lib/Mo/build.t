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

$main::count = 1;

package Foo;
use Mo 'build';
has 'foo' => (is => 'rw');
sub BUILD {
    my $self = shift;
    ::is_deeply(\@_, [qw(stuff 1)], "Foo's BUILD doesn't get the class name");
    $self->foo($main::count++);
}

package Bar;
use Mo;
extends 'Foo';
has 'bar' => (is => 'rw');

package Baz;
use Mo;
extends 'Bar';
has 'baz' => (is => 'rw');
sub BUILD {
    my $self = shift;
    ::is_deeply(\@_, [qw(stuff 1)], "Baz's BUILD doesn't get the class name");
    $self->baz($main::count++);
}

package Gorch;
use Mo;
extends 'Baz';
has 'gorch' => (is => 'rw');

package main;

my $g = Gorch->new(stuff => 1);
is $g->foo, 1, 'foo builds first';
is $g->baz, 2, 'baz builds second';

done_testing;
