#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 2;

use PerconaTest;
require "$trunk/bin/pt-config-diff";

my $cnf = '/tmp/12345/my.sandbox.cnf';
my $output;
my $retval;

# ############################################################################
# --ignore-variables
# ############################################################################

$output = output(
   sub { $retval = pt_config_diff::main(
      '/tmp/12345/my.sandbox.cnf',
      '/tmp/12346/my.sandbox.cnf',
   ) },
   stderr => 1,
);

like(
   $output,
   qr{port\s+12345\s+12346},
   "port is different"
);

$output = output(
   sub { $retval = pt_config_diff::main(
      '/tmp/12345/my.sandbox.cnf',
      '/tmp/12346/my.sandbox.cnf',
      '--ignore-variables', 'port',
   ) },
   stderr => 1,
);

like(
   $output,
   qr{port\s+12345\s+12346},
   "port is ignored"
);

# #############################################################################
# Done.
# #############################################################################
exit;
