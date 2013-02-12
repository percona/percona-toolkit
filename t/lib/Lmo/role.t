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

BEGIN {
   my $have_roles = eval { require Role::Tiny };
   plan skip_all => "Can't load Role::Tiny, not testing Roles"
      unless $have_roles;
}

{
  package One::P1; use Lmo::Role;
  has two => (is => 'ro', default => sub { 'two' });
  no Lmo::Role;

  package One::P2; use Lmo::Role;
  has three => (is => 'ro', default => sub { 'three' });
  no Lmo::Role;
  
  package One::P3; use Lmo::Role;
  has four => (is => 'ro', default => sub { 'four' });
  no Lmo::Role;

  package One; use Lmo;
  with qw( One::P1 One::P2 );
  has one => (is => 'ro', default => sub { 'one' });
}

my $combined = One->new();

ok $combined->does($_), "Does $_" for qw(One::P1 One::P2);

ok !$combined->does($_), "Doesn't $_" for qw(One::P3 One::P4);

is $combined->one, "one",     "attr default set from class";
is $combined->two, "two",     "attr default set from role";
is $combined->three, "three", "attr default set from role";

# Testing unimport

{
   package Two::P1; use Lmo::Role;
   has two => (is => 'ro', default => sub { 'two' });
   no Lmo::Role;

   package Two; use Lmo;
   with qw(Two::P1);
   has three => ( is => 'ro', default => sub { 'three' } );
   no Lmo;
}

my $two = Two->new();

is
   $two->two(),
   'two',
   "unimporting in a role doesn't remove new attributes";

for my $class ( qw( Two::P1 Two ) ) {
   ok !$class->can($_), "...but does remove $_ from $class" for qw(has with extends requires);
}

done_testing;
