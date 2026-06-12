#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More ;

use PerconaTest;
require "$trunk/bin/pt-replica-restart";

my $output;
my $cnf = '/tmp/12346/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-replica-restart -F $cnf h=127.1";
my $legacy_cmd = "$trunk/bin/pt-slave-restart -F $cnf h=127.1";

$output = `$cmd --help 2>&1`;
unlike(
   $output, 
   qr/pt-slave-restart is a link to pt-replica-restart/, 
   'Deprecation warning not printed for pt-replica-restart'
);

$output = `$legacy_cmd --help 2>&1`;
like(
   $output, 
   qr/pt-slave-restart is a link to pt-replica-restart/, 
   'Deprecation warning printed for pt-slave-restart'
);

done_testing();
exit;
