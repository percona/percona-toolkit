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

sub throws_ok (&;$) {
   my ( $code, $pat, $msg ) = @_;
   eval { $code->(); };
   like ( $EVAL_ERROR, $pat, $msg );
}

{
   package Metatest;
   use Lmo;

   has stuff => ( is => 'rw', required => 1 );
   has init_stuff1 => ( is => 'rw', init_arg => undef );
   has init_stuff2 => ( is => 'rw', init_arg => 'fancy_name' );
}
{
package Metatest::child;
   use Lmo;
   extends 'Metatest';

   has more_stuff => ( is => 'rw' );
}

my $obj = Metatest->new( stuff => 100 );

can_ok($obj, 'meta');

my $meta = $obj->meta();

is_deeply(
   [ sort $meta->attributes ],
   [ sort qw(stuff init_stuff1 init_stuff2) ],
   "->attributes works"
);

is_deeply(
   [ sort $meta->attributes_for_new ],
   [ sort qw(stuff fancy_name) ],
   "->attributes_for_new works"
);

# Do these BEFORE initializing ::extends
my $meta2 = Metatest::child->meta();
is_deeply(
   [ sort $meta2->attributes ],
   [ sort qw(stuff init_stuff1 init_stuff2 more_stuff) ],
   "->attributes works on a child class"
);

is_deeply(
   [ sort $meta2->attributes_for_new ],
   [ sort qw(stuff fancy_name more_stuff) ],
   "->attributes_for_new works in a child class"
);

my $meta3 = Metatest::child->new(stuff => 10)->meta();
is_deeply(
   [ sort $meta3->attributes ],
   [ sort qw(stuff init_stuff1 init_stuff2 more_stuff) ],
   "->attributes works on an initialized child class"
);

is_deeply(
   [ sort $meta3->attributes_for_new ],
   [ sort qw(stuff fancy_name more_stuff) ],
   "->attributes_for_new works in an initialized child class"
);

throws_ok { Metatest::child->new() } qr/\QAttribute (stuff) is required for Metatest::child/;

done_testing;
