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
require "$trunk/bin/pt-slave-restart";

if ( $sandbox_version lt '5.6' ) {
   plan skip_all => 'MySQL Version ' . $sandbox_version 
                     . ' < 5.6, GTID is not available, skipping tests';
}

diag("Stopping/reconfiguring/restarting sandboxes 12345, 12346 and 12347");

diag(`$trunk/sandbox/test-env stop >/dev/null`);
diag(`REPLICATION_THREADS=2 GTID=1 $trunk/sandbox/test-env start >/dev/null`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh  = $sb->get_dbh_for('master');
my $slave_dbh   = $sb->get_dbh_for('slave1');
my $slave2_dbh  = $sb->get_dbh_for('slave2');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}

# #############################################################################
# pt-slave-restart should exit!
# #############################################################################
# Start an instance
my $output=`$trunk/bin/pt-slave-restart --run-time=1s -h 127.0.0.1 -P 12346 -u msandbox -p msandbox 2>&1`;

like(
   $output,
   qr/Cannot skip transactions properly.*slave_parallel_workers/,
   "pt-slave-restart exits with multiple replication threads"
);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -f /tmp/pt-slave-re*`);
diag(`$trunk/sandbox/test-env stop >/dev/null`);
diag(`$trunk/sandbox/test-env start >/dev/null`);

ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
