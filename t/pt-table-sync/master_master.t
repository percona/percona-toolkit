#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 1;

use MaatkitTest;
require "$trunk/bin/pt-table-sync";

my $output;

# #############################################################################
# Ensure that syncing master-master works OK
# #############################################################################

# Sometimes I skip this test if I'm proving mk-table-sync over and over.
SKIP: {
   skip "I'm impatient", 1 if 0;

   diag(`$trunk/sandbox/start-sandbox master-master 12348 12349 >/dev/null`);
   diag(`/tmp/12348/use -e 'CREATE DATABASE test'`);
   diag(`/tmp/12348/use < $trunk/t/pt-table-sync/samples/before.sql`);

   # Make master2 different from master1
   diag(`/tmp/12349/use -e 'set sql_log_bin=0;update test.test1 set b="mm" where a=1'`);

   # This will make master1's data match the changed data on master2 (that is not
   # a typo).
   `$trunk/bin/pt-table-sync --no-check-slave --sync-to-master --print --execute h=127.0.0.1,P=12348,u=msandbox,p=msandbox,D=test,t=test1`;
   sleep 1;

   $output = `/tmp/12348/use -e 'select b from test.test1 where a=1' -N`;
   like($output, qr/mm/, 'Master-master sync worked');

   diag(`$trunk/sandbox/stop-sandbox remove 12348 12349 >/dev/null`);
};

# #############################################################################
# Done.
# #############################################################################
exit;
