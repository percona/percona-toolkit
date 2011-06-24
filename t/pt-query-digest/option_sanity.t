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

use MaatkitTest;

# #############################################################################
# Test cmd line op sanity.
# #############################################################################
my $output = `$trunk/bin/pt-query-digest --review h=127.1,P=12345,u=msandbox,p=msandbox`;
like($output, qr/--review DSN requires a D/, 'Dies if no D part in --review DSN');

$output = `$trunk/bin/pt-query-digest --review h=127.1,P=12345,u=msandbox,p=msandbox,D=test`;
like($output, qr/--review DSN requires a D/, 'Dies if no t part in --review DSN');


# #############################################################################
# Done.
# #############################################################################
exit;
