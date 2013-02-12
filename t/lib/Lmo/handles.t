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


# -------------------------------------------------------------------
# HASH handles
# -------------------------------------------------------------------
# the canonical form of of the 'handles'
# option is the hash ref mapping a
# method name to the delegated method name

{
    package Foo;
    use Lmo qw(is required handles default builder);

    has 'bar' => (is => 'rw', default => sub { 10 });

    sub baz { 42 }

    package Bar;
    use Lmo qw(is required handles default builder);

    has 'foo' => (
        is      => 'rw',
        default => sub { Foo->new },
        handles => {
            'foo_bar' => 'bar',
            foo_baz   => 'baz',
            'foo_bar_to_20' => [ bar => 20 ],
        },
    );
}

my $bar = Bar->new;
isa_ok($bar, 'Bar');

ok($bar->foo, '... we have something in bar->foo');
isa_ok($bar->foo, 'Foo');

is($bar->foo->bar, 10, '... bar->foo->bar returned the right default');

can_ok($bar, 'foo_bar');
is($bar->foo_bar, 10, '... bar->foo_bar delegated correctly');

# change the value ...

$bar->foo->bar(30);

# and make sure the delegation picks it up

is($bar->foo->bar, 30, '... bar->foo->bar returned the right (changed) value');
is($bar->foo_bar, 30, '... bar->foo_bar delegated correctly');

# change the value through the delegation ...

$bar->foo_bar(50);

# and make sure everyone sees it

is($bar->foo->bar, 50, '... bar->foo->bar returned the right (changed) value');
is($bar->foo_bar, 50, '... bar->foo_bar delegated correctly');

# change the object we are delegating too

my $foo = Foo->new(bar => 25);
isa_ok($foo, 'Foo');

is($foo->bar, 25, '... got the right foo->bar');

local $@;
eval { $bar->foo($foo) };
is $@, '', '... assigned the new Foo to Bar->foo';

is($bar->foo, $foo, '... assigned bar->foo with the new Foo');

is($bar->foo->bar, 25, '... bar->foo->bar returned the right result');
is($bar->foo_bar, 25, '... and bar->foo_bar delegated correctly again');

# curried handles
$bar->foo_bar_to_20;
is($bar->foo_bar, 20, '... correctly curried a single argument');

# -------------------------------------------------------------------
# ARRAY handles
# -------------------------------------------------------------------
# we also support an array based format
# which assumes that the name is the same
# on either end

{
    package Engine;
    use Lmo qw(is required handles default builder);

    sub go   { 'Engine::go'   }
    sub stop { 'Engine::stop' }

    package Car;
    use Lmo qw(is required handles default builder);

    has 'engine' => (
        is      => 'rw',
        default => sub { Engine->new },
        handles => [ 'go', 'stop' ]
    );
}

my $car = Car->new;
isa_ok($car, 'Car');

isa_ok($car->engine, 'Engine');
can_ok($car->engine, 'go');
can_ok($car->engine, 'stop');

is($car->engine->go, 'Engine::go', '... got the right value from ->engine->go');
is($car->engine->stop, 'Engine::stop', '... got the right value from ->engine->stop');

can_ok($car, 'go');
can_ok($car, 'stop');

is($car->go, 'Engine::go', '... got the right value from ->go');
is($car->stop, 'Engine::stop', '... got the right value from ->stop');

# -------------------------------------------------------------------
# REGEXP handles
# -------------------------------------------------------------------
# and we support regexp delegation

{
    package Baz;
    use Lmo qw(is required handles default builder);

    sub foo { 'Baz::foo' }
    sub bar { 'Baz::bar' }
    sub boo { 'Baz::boo' }

    package Baz::Proxy1;
    use Lmo qw(is required handles default builder);

    has 'baz' => (
        is      => 'ro',
        isa     => 'Baz',
        default => sub { Baz->new },
        handles => qr/.*/
    );

    package Baz::Proxy2;
    use Lmo qw(is required handles default builder);

    has 'baz' => (
        is      => 'ro',
        isa     => 'Baz',
        default => sub { Baz->new },
        handles => qr/.oo/
    );

    package Baz::Proxy3;
    use Lmo qw(is required handles default builder);

    has 'baz' => (
        is      => 'ro',
        isa     => 'Baz',
        default => sub { Baz->new },
        handles => qr/b.*/
    );
}

{
    my $baz_proxy = Baz::Proxy1->new;
    isa_ok($baz_proxy, 'Baz::Proxy1');

    can_ok($baz_proxy, 'baz');
    isa_ok($baz_proxy->baz, 'Baz');

    can_ok($baz_proxy, 'foo');
    can_ok($baz_proxy, 'bar');
    can_ok($baz_proxy, 'boo');

    is($baz_proxy->foo, 'Baz::foo', '... ->foo got the right proxied return value');
    is($baz_proxy->bar, 'Baz::bar', '... ->bar got the right proxied return value');
    is($baz_proxy->boo, 'Baz::boo', '... ->boo got the right proxied return value');
}
{
    my $baz_proxy = Baz::Proxy2->new;
    isa_ok($baz_proxy, 'Baz::Proxy2');

    can_ok($baz_proxy, 'baz');
    isa_ok($baz_proxy->baz, 'Baz');

    can_ok($baz_proxy, 'foo');
    can_ok($baz_proxy, 'boo');

    is($baz_proxy->foo, 'Baz::foo', '... ->foo got the right proxied return value');
    is($baz_proxy->boo, 'Baz::boo', '... ->boo got the right proxied return value');
}
{
    my $baz_proxy = Baz::Proxy3->new;
    isa_ok($baz_proxy, 'Baz::Proxy3');

    can_ok($baz_proxy, 'baz');
    isa_ok($baz_proxy->baz, 'Baz');

    can_ok($baz_proxy, 'bar');
    can_ok($baz_proxy, 'boo');

    is($baz_proxy->bar, 'Baz::bar', '... ->bar got the right proxied return value');
    is($baz_proxy->boo, 'Baz::boo', '... ->boo got the right proxied return value');
}

# -------------------------------------------------------------------
# ROLE handles
# -------------------------------------------------------------------
=begin
{
    package Foo::Bar;
    use Moose::Role;

    requires 'foo';
    requires 'bar';

    package Foo::Baz;
    use Lmo qw(is required handles default builder);

    sub foo { 'Foo::Baz::FOO' }
    sub bar { 'Foo::Baz::BAR' }
    sub baz { 'Foo::Baz::BAZ' }

    package Foo::Thing;
    use Lmo qw(is required handles default builder);

    has 'thing' => (
        is      => 'rw',
        isa     => 'Foo::Baz',
        handles => 'Foo::Bar',
    );

    package Foo::OtherThing;
    use Lmo qw(is required handles default builder);
    use Moose::Util::TypeConstraints;

    has 'other_thing' => (
        is      => 'rw',
        isa     => 'Foo::Baz',
        handles => Mooose::Util::TypeConstraints::find_type_constraint('Foo::Bar'),
    );
}

{
    my $foo = Foo::Thing->new(thing => Foo::Baz->new);
    isa_ok($foo, 'Foo::Thing');
    isa_ok($foo->thing, 'Foo::Baz');

    ok($foo->meta->has_method('foo'), '... we have the method we expect');
    ok($foo->meta->has_method('bar'), '... we have the method we expect');
    ok(!$foo->meta->has_method('baz'), '... we dont have the method we expect');

    is($foo->foo, 'Foo::Baz::FOO', '... got the right value');
    is($foo->bar, 'Foo::Baz::BAR', '... got the right value');
    is($foo->thing->baz, 'Foo::Baz::BAZ', '... got the right value');
}

{
    my $foo = Foo::OtherThing->new(other_thing => Foo::Baz->new);
    isa_ok($foo, 'Foo::OtherThing');
    isa_ok($foo->other_thing, 'Foo::Baz');

    ok($foo->meta->has_method('foo'), '... we have the method we expect');
    ok($foo->meta->has_method('bar'), '... we have the method we expect');
    ok(!$foo->meta->has_method('baz'), '... we dont have the method we expect');

    is($foo->foo, 'Foo::Baz::FOO', '... got the right value');
    is($foo->bar, 'Foo::Baz::BAR', '... got the right value');
    is($foo->other_thing->baz, 'Foo::Baz::BAZ', '... got the right value');
}
=cut
# -------------------------------------------------------------------
# AUTOLOAD & handles
# -------------------------------------------------------------------

{
    package Foo::Autoloaded;
    use Lmo qw(is required handles default builder);
    
    sub AUTOLOAD {
        my $self = shift;

        my $name = our $AUTOLOAD;
        $name =~ s/.*://; # strip fully-qualified portion

        if (@_) {
            return $self->{$name} = shift;
        } else {
            return $self->{$name};
        }
    }

    package Bar::Autoloaded;
    use Lmo qw(is required handles default builder);

    has 'foo' => (
        is      => 'rw',
        default => sub { Foo::Autoloaded->new },
        handles => { 'foo_bar' => 'bar' }
    );

    package Baz::Autoloaded;
    use Lmo qw(is required handles default builder);

    has 'foo' => (
        is      => 'rw',
        default => sub { Foo::Autoloaded->new },
        handles => ['bar']
    );

    package Goorch::Autoloaded;
    use Lmo qw(is required handles default builder);

    eval {
        has 'foo' => (
            is      => 'rw',
            default => sub { Foo::Autoloaded->new },
            handles => qr/bar/
        );
    };
    ::isnt($@, '', '... you cannot delegate to AUTOLOADED class with regexp' );
}

# check HASH based delegation w/ AUTOLOAD

{
    my $bar = Bar::Autoloaded->new;
    isa_ok($bar, 'Bar::Autoloaded');

    ok($bar->foo, '... we have something in bar->foo');
    isa_ok($bar->foo, 'Foo::Autoloaded');

    # change the value ...

    $bar->foo->bar(30);

    # and make sure the delegation picks it up

    is($bar->foo->bar, 30, '... bar->foo->bar returned the value changed by ->foo->bar()');
    is($bar->foo_bar, 30, '... bar->foo_bar getter delegated correctly');

    # change the value through the delegation ...

    $bar->foo_bar(50);

    # and make sure everyone sees it

    is($bar->foo->bar, 50, '... bar->foo->bar returned the value changed by ->foo_bar()');
    is($bar->foo_bar, 50, '... bar->foo_bar getter delegated correctly');

    # change the object we are delegating too

    my $foo = Foo::Autoloaded->new;
    isa_ok($foo, 'Foo::Autoloaded');

    $foo->bar(25);

    is($foo->bar, 25, '... got the right foo->bar');

    local $@;
    eval { $bar->foo($foo) };
    is($@, '', '... assigned the new Foo to Bar->foo' );

    is($bar->foo, $foo, '... assigned bar->foo with the new Foo');

    is($bar->foo->bar, 25, '... bar->foo->bar returned the right result');
    is($bar->foo_bar, 25, '... and bar->foo_bar delegated correctly again');
}

# check ARRAY based delegation w/ AUTOLOAD

{
    my $baz = Baz::Autoloaded->new;
    isa_ok($baz, 'Baz::Autoloaded');

    ok($baz->foo, '... we have something in baz->foo');
    isa_ok($baz->foo, 'Foo::Autoloaded');

    # change the value ...

    $baz->foo->bar(30);

    # and make sure the delegation picks it up

    is($baz->foo->bar, 30, '... baz->foo->bar returned the right (changed) value');
    is($baz->bar, 30, '... baz->foo_bar delegated correctly');

    # change the value through the delegation ...

    $baz->bar(50);

    # and make sure everyone sees it

    is($baz->foo->bar, 50, '... baz->foo->bar returned the right (changed) value');
    is($baz->bar, 50, '... baz->foo_bar delegated correctly');

    # change the object we are delegating too

    my $foo = Foo::Autoloaded->new;
    isa_ok($foo, 'Foo::Autoloaded');

    $foo->bar(25);

    is($foo->bar, 25, '... got the right foo->bar');

    is( exception {
        $baz->foo($foo);
    }, undef, '... assigned the new Foo to Baz->foo' );

    is($baz->foo, $foo, '... assigned baz->foo with the new Foo');

    is($baz->foo->bar, 25, '... baz->foo->bar returned the right result');
    is($baz->bar, 25, '... and baz->foo_bar delegated correctly again');
}

# Make sure that a useful error message is thrown when the delegation target is
# not an object
{
    my $i = Bar->new(foo => undef);
    local $@;
    eval { $i->foo_bar };
    like($@, qr/is not defined/, 'useful error if delegating from undef' );

    my $j = Bar->new(foo => []);
    local $@;
    eval { $j->foo_bar };
    like($@, qr/is not an object \(got 'ARRAY/, '... or from an unblessed reference' );

    my $k = Bar->new(foo => "Foo");
    local $@;
    eval { $k->foo_baz };
    is( $@, '', "but not for class name" );
}

{
    package Delegator;
    use Lmo qw(is required handles default builder);

    sub full { 1 }
    sub stub;

    local $@;
    eval {
       has d1 => (
                isa     => 'X',
                handles => ['full'],
            );
    };
    ::like(
        $@,
        qr/\QYou cannot overwrite a locally defined method (full) with a delegation/,
        'got an error when trying to declare a delegation method that overwrites a local method'
    );

    local $@;
    eval { has d2 => (
                isa     => 'X',
                handles => ['stub'],
            );
    };
    ::is(
        $@,
        '',
        'no error when trying to declare a delegation method that overwrites a stub method'
    );
}


done_testing;
