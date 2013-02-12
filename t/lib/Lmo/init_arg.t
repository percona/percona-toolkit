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



{
    package Foo;
    use Lmo qw( is init_arg );

    eval {
        has 'foo' => (
            is => "rw",
            init_arg => undef,
        );
    };
    ::ok(!$@, '... created the attr okay');
}

{
    my $foo = Foo->new( foo => "bar" );
    isa_ok($foo, 'Foo');

    is( $foo->foo, undef, "field is not set via init arg" );

    $foo->foo("blah");

    is( $foo->foo, "blah", "field is set via setter" );
}

{
    package Foo;

    eval {
        has 'foo2' => (
            is => "rw",
            init_arg => undef,
        );
    };
    ::ok(!$@, '... adding a second attribute with init_arg works');
}

{
    my $foo = Foo->new( foo => "bar", foo2 => "baz" );

    is( $foo->foo, undef, "foo is not set via init arg" );
    is( $foo->foo2, undef, "foo2 is not set via init arg" );

    $foo->foo("blah");
    $foo->foo2("bluh");

    is( $foo->foo, "blah", "foo is set via setter" );
    is( $foo->foo2, "bluh", "foo2 is set via setter" );
}

{
    package Foo2;
    use Lmo qw( is init_arg clearer default );

    my $counter;
    eval {
        has 'auto_foo' => (
            is       => "ro",
            init_arg => undef,
            default  => sub { $counter++ ? "Foo" : "Bar" },
            clearer  => 'clear_auto_foo',
        );
    };
    ::ok(!$@, '... attribute with init_arg+default+clearer+is works');
}

{
    my $foo = Foo2->new( auto_foo => 1234 );

    is( $foo->auto_foo, "Bar", "auto_foo is not set via init arg, but by the default" );

    $foo->clear_auto_foo();

    is( $foo->auto_foo, "Foo", "auto_foo calls default again if cleared" );
}

done_testing;
