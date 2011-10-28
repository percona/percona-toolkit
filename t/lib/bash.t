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
push @ARGV, "$trunk/t/lib/bash/*.sh" unless @ARGV;

$ENV{LIB_DIR}   = "$trunk/lib/bash";
$ENV{T_LIB_DIR} = "$trunk/t/lib";

system("$trunk/util/test-bash-functions $trunk/t/lib/samples/bash/dummy.sh @ARGV");

exit;
