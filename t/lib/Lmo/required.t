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
package Foo::required;
use Lmo qw(required);

has 'stuff' => (required => 1);
has 'stuff2' => (required => 1);
has 'foo' => ();
#============
package Foo::required_is;
use Lmo qw(required);

has 'stuff' => (required => 1, is => 'ro');
#============

package main;

my $f0 = eval { Foo::required->new(stuff2 => 'foobar') };
like $@, qr/^\QAttribute (stuff) is required/, 'Lmo dies when a required value is not provided';

my $f = Foo::required->new(stuff => 'fubar', stuff2 => 'foobar');
is $f->stuff, 'fubar', 'Object is correctly initialized when required values are provided';

my $f2 = Foo::required_is->new(stuff => 'fubar');
is $f2->stuff, 'fubar', 'Object is correctly initialized when required is combined with is';

done_testing;
