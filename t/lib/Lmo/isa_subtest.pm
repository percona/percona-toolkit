BEGIN {
   # If we can't load ::PP, the bug can't happen on this perl, so it's a pass
   eval { require Scalar::Util::PP } or do { exit 0 };
   *Scalar::Util:: = \*Scalar::Util::PP::;
   $INC{"Scalar/Util.pm"} = __FILE__;
};

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings;

{
   package isa_subtest;
   use Lmo;

   has attr => (
      is  => 'rw',
      isa => 'Int',
   );

   1;
}

isa_subtest->new(attr => 100);
