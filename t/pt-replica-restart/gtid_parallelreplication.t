#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-replica-restart";

if ( $sandbox_version lt '5.6' ) {
   plan skip_all => 'MySQL Version ' . $sandbox_version 
                     . ' < 5.6, GTID is not available, skipping tests';
}

diag("Stopping/reconfiguring/restarting sandboxes 12345, 12346 and 12347");

diag(`$trunk/sandbox/test-env stop >/dev/null`);
diag(`REPLICATION_THREADS=2 GTID=ON_PERMISSIVE $trunk/sandbox/test-env start >/dev/null`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh  = $sb->get_dbh_for('source');
my $replica_dbh   = $sb->get_dbh_for('replica1');
my $replica2_dbh  = $sb->get_dbh_for('replica2');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
}

# #############################################################################
# pt-replica-restart should exit!
# #############################################################################
# Start an instance
my $output=`$trunk/bin/pt-replica-restart --run-time=1s -h 127.0.0.1 -P 12346 -u msandbox -p msandbox 2>&1`;

like(
   $output,
   qr/Cannot skip transactions properly.*${replica_name}_parallel_workers/,
   "pt-replica-restart exits with multiple replication threads"
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -f /tmp/pt-replica-re*`);

diag(`$trunk/sandbox/test-env stop >/dev/null`);
diag(`$trunk/sandbox/test-env start >/dev/null`);
#
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
