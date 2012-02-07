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

my $tool = "pt-ioprofile";
push @ARGV, "$trunk/t/$tool/*.sh" unless @ARGV;

$ENV{BIN_DIR} = "$trunk/bin";
$ENV{T_DIR}   = "$trunk/t/$tool";

system("$trunk/util/test-bash-functions $trunk/t/lib/samples/bash/dummy.sh @ARGV");

# #############################################################################
# Done.
# #############################################################################
exit;
