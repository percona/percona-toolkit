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

#if ( !$ENV{SLOW_TESTS} ) {
#   plan skip_all => "pt-table-checksum/throttle.t is a top 5 slowest file; set SLOW_TESTS=1 to enable it.";
#}

$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica2_dbh = $sb->get_dbh_for('replica2');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
}
else {
   plan tests => 8;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($source_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', '',
                  '--progress', 'time,1');
my $output;
my $row;
my $exit_status;

# Create the checksum table, else stopping the replica below
# will cause the tool to wait forever for the --replicate
# table to replicate to the stopped replica.
pt_table_checksum::main(@args, qw(-t sakila.city --quiet));

# ############################################################################
# --check-replica-lag
# ############################################################################

# Stop replica1.
$sb->wait_for_replicas();
$replica1_dbh->do("stop ${replica_name} sql_thread");
wait_until(sub {
   my $ss = $replica1_dbh->selectrow_hashref("SHOW ${replica_name} STATUS");
   return $ss->{"${replica_name}_sql_running"} eq 'Yes';
});

# Try to checksum, but since replica1 is stopped, the tool should
# wait for it to stop "lagging".
($output) = PerconaTest::full_output(
   sub { pt_table_checksum::main(@args, qw(-t sakila.city)) },
   wait_for => 10,
);

like(
   $output,
   qr/Replica h=127.0.0.1,P=12346 is stopped/,
   "Waits for stopped replica"
);

# Checksum but only use replica2 to check for lag.
$exit_status = pt_table_checksum::main(@args, qw(-t sakila.city --quiet),
   qw(--no-replicate-check), '--check-replica-lag', 'P=12347');

is(
   $exit_status,
   0,
   "Ignores replica1 when --check-replica-lag=replica2"
);

unlike(
   $output,
   qr/Option --check-slave-lag is deprecated and will be removed in future versions./,
   'Deprecation warning not printed when option --check-replica-lag provided'
) or diag($output);

$row = $source_dbh->selectall_arrayref("select * from percona.checksums where db='sakila' and tbl='city'");
is(
   scalar @$row,
   1,
   "Checksummed table"
);

$source_dbh->do("delete from percona.checksums where db='sakila' and tbl='city'");

# Checksum but only use replica2 to check for lag with deprecated --check-slave-lag.
($output, $exit_status) = full_output(
   sub {
      pt_table_checksum::main(@args, 
         qw(-t sakila.city --quiet),
         qw(--no-replicate-check), '--check-slave-lag', 'P=12347')
   },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Ignores replica1 when --check-slave-lag=replica2"
);

like(
   $output,
   qr/Option --check-slave-lag is deprecated and will be removed in future versions./,
   'Deprecation warning printed when option --check-slave-lag provided'
) or diag($output);

$row = $source_dbh->selectall_arrayref("select * from percona.checksums where db='sakila' and tbl='city'");
is(
   scalar @$row,
   1,
   "Checksummed table"
);

$replica1_dbh->do("START ${replica_name} sql_thread");
$replica2_dbh->do("STOP ${replica_name}");
$replica2_dbh->do("START ${replica_name}");
$sb->wait_for_replicas();

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
