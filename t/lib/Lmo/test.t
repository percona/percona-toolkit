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

#============
package Foo;
use Lmo;

has 'this';

#============
package main;

ok defined(&Foo::has), 'Lmo exports has';
ok defined(&Foo::extends), 'Lmo exports extends';
ok not(defined(&Foo::new)), 'Lmo does not export new';
ok 'Foo'->isa('Lmo::Object'), 'Foo isa Lmo::Object';
is "@Foo::ISA", "Lmo::Object", '@Foo::ISA is Lmo::Object';
ok 'Foo'->can('new'), 'Foo can new';
ok 'Foo'->can('this'), 'Foo can this';

my $f = 'Foo'->new;

ok not(exists($f->{this})), 'this does not exist';
ok not(defined($f->this)), 'this is not defined';

$f->this("it");

is $f->this, 'it', 'this is it';
is $f->{this}, 'it', '{this} is it';

$f->this("that");

is $f->this, 'that', 'this is that';
is $f->{this}, 'that', '{this} is that';

$f->this(undef);

ok not(defined($f->this)), 'this is not defined';
ok not(defined($f->{this})), '{this} is not defined';

#============
package Bar;
use Lmo 'builder', 'default';
extends 'Foo';

has 'that';
has them => default => sub {[]};
has plop => (
    is => 'xy',
    default => sub { my $self = shift; "plop: " . $self->that },
);
has 'plip';
has bridge => builder => 'bridge_builder';
use constant bridge_builder => 'A Bridge';
has guess => (
    default => sub {'me me me'},
    builder => 'bridge_builder',
);

#============
package main;

ok 'Bar'->isa('Lmo::Object'), 'Bar isa Lmo::Object';
ok 'Bar'->isa('Foo'), 'Bar isa Foo';
is "@Bar::ISA", 'Foo', '@Bar::ISA is Foo';
ok 'Bar'->can('new'), 'Bar can new';
ok 'Bar'->can('this'), 'Bar can this';
ok 'Bar'->can('that'), 'Bar can that';
ok 'Bar'->can('them'), 'Bar can them';

my $b = Bar->new(
    this => 'thing',
    that => 'thong',
);

is ref($b), 'Bar', 'Object created';
ok $b->isa('Foo'), 'Inheritance works';
ok $b->isa('Lmo::Object'), 'Bar isa Lmo::Object since Foo isa Lmo::Object';
is $b->this, 'thing', 'Read works in parent class';
is $b->that, 'thong', 'Read works in current class';
is ref($b->them), 'ARRAY', 'default works';
is $b->plop, 'plop: thong', 'default works as a method call';
$b->that("thung");
$b->plop(undef);
ok not(defined $b->plop), 'plop is undef';
delete $b->{plop};
is $b->plop, 'plop: thung', 'default works again';
$b->that("thyng");
is $b->plop, 'plop: thung', 'default works again';
is $b->plip, undef, 'no default is undef';
is $b->bridge, 'A Bridge', 'builder works';
is $b->guess, 'me me me', 'default trumps builder';

#============
package Baz;
use Lmo 'build';

has 'foo';

sub BUILD {
    my $self = shift;
    $self->foo(5);
}

#============
package Maz;
use Lmo;
extends 'Baz';

has 'bar';

sub BUILD {
    my $self = shift;
    $self->SUPER::BUILD();
    $self->bar(7);
}

#============
package main;

my $baz = Baz->new;
is $baz->foo, 5, 'BUILD works';

$_ = 5;
my $maz = Maz->new;
is $_, 5, '$_ is untouched';
is $maz->foo, 5, 'BUILD works again';
is $maz->bar, 7, 'BUILD works in parent class';

done_testing;
