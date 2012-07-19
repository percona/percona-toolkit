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

sub dies_ok (&;$) {
  my $code = shift;
  my $name = shift;

  ok( !eval{ $code->() }, $name )
      or diag( "expected an exception but none was raised" );
}

sub lives_ok (&;$) {
  my $code = shift;
  my $name = shift;

  eval{ $code->() };
  is($@, '', $name );
}

package Foo::isa;
use Mo qw(isa);

my @types = qw(Bool Num Int Str ArrayRef CodeRef HashRef RegexpRef);
my @refs = ([], sub { }, {}, qr( ));
has( "my$_" => ( isa => $_ ) ) for @types;
has( myFoo => ( isa => "Foo::isa" ) );

package main;

my $foo = Foo::isa->new( myStr => "abcdefg" );

# Bool:
lives_ok { ok !$foo->myBool(undef) } "Bool attr set to undef";
lives_ok { is $foo->myBool(1), 1 }   "Bool attr set to 1";
is $foo->myBool, 1, "new value of \$foo->myBool as expected";
lives_ok { is $foo->myBool(1e0), 1 } "Bool attr set to 1e0";
dies_ok { $foo->myBool("1f0") }       "Bool attr set to 1f0 dies";
lives_ok { is $foo->myBool(""), "" } "Bool attr set to empty string";
is $foo->myBool, "", "new value of \$foo->myBool as expected";
lives_ok { is $foo->myBool(0), 0 }   "Bool attr set to 0";
lives_ok { is $foo->myBool(0.0), 0 } "Bool attr set to 0.0";
lives_ok { is $foo->myBool(0e0), 0 } "Bool attr set to 0e0";
dies_ok { $foo->myBool("0.0") }       "Bool attr set to stringy 0.0 dies";

# Bool tests from Mouse:
open(my $FH, "<", $0) or die "Could not open $0 for the test";
my $msg = q(Bool rejects anything which is not a 1 or 0 or "" or undef");
lives_ok { $foo->myBool(0) }              $msg;
lives_ok { $foo->myBool(1) }              $msg;
dies_ok { $foo->myBool(100) }             $msg;
lives_ok { $foo->myBool("") }             $msg;
dies_ok { $foo->myBool("Foo") }           $msg;
dies_ok { $foo->myBool([]) }              $msg;
dies_ok { $foo->myBool({}) }              $msg;
dies_ok { $foo->myBool(sub {}) }          $msg;
dies_ok { $foo->myBool(\"") }             $msg;
dies_ok { $foo->myBool(*STDIN) }          $msg;
dies_ok { $foo->myBool(\*STDIN) }         $msg;
dies_ok { $foo->myBool($FH) }             $msg;
dies_ok { $foo->myBool(qr/../) }          $msg;
dies_ok { $foo->myBool(bless {}, "Foo") } $msg;
lives_ok { $foo->myBool(undef) }          $msg;

# Num:
lives_ok { is $foo->myNum(5.5), 5.5 } "Num attr set to decimal";
is $foo->myNum, 5.5, "new value of \$foo->myNum as expected";
lives_ok { is $foo->myNum(5), 5 } "Num attr set to integer";
lives_ok { is $foo->myNum(5e0), 5 } "Num attr set to 5e0";
dies_ok { $foo->myBool("5f0") }       "Bool attr set to 5f0 dies";
lives_ok { is $foo->myNum("5.5"), 5.5 } "Num attr set to stringy decimal";

# Int:
lives_ok { is $foo->myInt(0), 0 }   "Int attr set to 0";
lives_ok { is $foo->myInt(1), 1 }   "Int attr set to 1";
lives_ok { is $foo->myInt(1e0), 1 } "Int attr set to 1e0";
is $foo->myInt, 1, "new value of \$foo->myInt as expected";
dies_ok { $foo->myInt("") } "Int attr set to empty string dies";
dies_ok { $foo->myInt(5.5) } "Int attr set to decimal dies";

# Str:
is $foo->myStr, "abcdefg", "Str passed to constructor accepted";
lives_ok { is $foo->myStr("hijklmn"), "hijklmn" } "Str attr set to a string";
is $foo->myStr, "hijklmn", "new value of \$foo->myStr as expected";
lives_ok { is $foo->myStr(5.5), 5.5 } "Str attr set to a decimal value";

# Class instance:
lives_ok { is $foo->myFoo($foo), $foo } "Class instance attr set to self";
isa_ok $foo->myFoo, "Foo::isa", "new value of \$foo->myFoo as expected";
dies_ok { $foo->myFoo({}) } "Class instance attr set to hash dies";

# Class name:
my $class = ref($foo);
lives_ok { is $foo->myFoo($class), $class } "Class instance attr set to classname";
is $foo->myFoo, $class, "new value of \$foo->myFoo as expected";

# Refs:
for my $i (4..7) {
    my $method = "my" . $types[$i];
    lives_ok(
        sub { $foo->$method($refs[$i - 4]) },
        "$types[$i] attr set to correct reference type" ); }
for my $i (4..7) {
    my $method = "my" . $types[$i];
    dies_ok(
        sub { $foo->$method($refs[(3 + $i) % 4]) },
        "$types[$i] attr set to incorrect reference type dies" ); }

# All but Bool vs undef:
for my $type (@types[1..$#types]) {
    my $method = "my$type";
    dies_ok { $foo->$method(undef) } "$type attr set to undef dies" }

done_testing;
