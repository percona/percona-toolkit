#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use PerconaTest;

my ($tool) = $PROGRAM_NAME =~ m/([\w-]+)\.t$/;
push @ARGV, "$trunk/t/$tool/*.sh" unless @ARGV;
system("$trunk/util/test-bash-functions $trunk/bin/$tool @ARGV");

require Test::More;
Test::More->import( tests => 3 );
use File::Temp qw( tempdir );

local $ENV{PTDEBUG} = "";

#
# --tempdir
#
my $dir = tempdir( CLEANUP => 1 );

`$trunk/bin/$tool --sleep 1 --tempdir $dir`;

ok(
   -e $dir,
   "Using --tempdir doesn't mistakenly delete the target dir"
);

my @files = glob("$dir/*");

is(
   scalar @files,
   14,
   "And leaves all files in there"
);

undef($dir);

#
# --dump-schemas
#

my $out = `$trunk/bin/$tool --sleep 1 --dump-schemas mysql`;

like(
   $out,
   qr/Database Tables Views SPs Trigs Funcs   FKs Partn\s+\Q{chosen}\E/,
   "--dump-schemas works"
);

exit;
