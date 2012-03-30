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

use Test::More tests => 6;
use File::Temp qw( tempdir );

local $ENV{PTDEBUG} = "";

#
# --save-samples
#

my $dir = tempdir( "percona-testXXXXXXXX", CLEANUP => 1 );

`$trunk/bin/$tool --sleep 1 --save-samples $dir -- --defaults-file=/tmp/12345/my.sandbox.cnf`;

ok(
   -e $dir,
   "Using --save-samples doesn't mistakenly delete the target dir"
);

my @files = glob("$dir/*");

is(
   scalar @files,
   13,
   "And leaves all files in there"
);

undef($dir);

#
# --databases
#

my $out = `$trunk/bin/$tool --sleep 1 --databases mysql 2>/dev/null -- --defaults-file=/tmp/12345/my.sandbox.cnf`;

like(
   $out,
   qr/Database Tables Views SPs Trigs Funcs   FKs Partn\s+\Qmysql\E/,
   "--databases works"
);

# --read-samples
for my $i (2..4) {
   ok(
      no_diff(
         sub {
            local $ENV{_NO_FALSE_NEGATIVES} = 1;
            print `$trunk/bin/$tool --read-samples $trunk/t/pt-mysql-summary/samples/temp00$i  -- --defaults-file=/tmp/12345/my.sandbox.cnf | tail -n+3 | perl -wlnpe 's/Skipping schema analysis.*/Skipping schema analysis/'`
         },
         "t/pt-mysql-summary/samples/expected_output_temp00$i.txt",
      ),
      "--read-samples works for t/pt-mysql-summary/temp00$i",
   );
}

exit;
