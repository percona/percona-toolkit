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

if ( !$ENV{SLOW_TESTS} ) {
   plan skip_all => "pt-table-checksum/throttle.t is a top 5 slowest file; set SLOW_TESTS=1 to enable it.";
}

$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');
my $slave2_dbh = $sb->get_dbh_for('slave2');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}
else {
   plan tests => 4;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', '',
                  '--progress', 'time,1');
my $output;
my $row;
my $exit_status;

# Create the checksum table, else stopping the slave below
# will cause the tool to wait forever for the --replicate
# table to replicate to the stopped slave.
pt_table_checksum::main(@args, qw(-t sakila.city --quiet));

# ############################################################################
# --check-slave-lag
# ############################################################################

# Stop slave1.
$sb->wait_for_slaves();
$slave1_dbh->do('stop slave sql_thread');
wait_until(sub {
   my $ss = $slave1_dbh->selectrow_hashref("SHOW SLAVE STATUS");
   return $ss->{slave_sql_running} eq 'Yes';
});

# Try to checksum, but since slave1 is stopped, the tool should
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

# Checksum but only use slave2 to check for lag.
$exit_status = pt_table_checksum::main(@args, qw(-t sakila.city --quiet),
   qw(--no-replicate-check), '--check-slave-lag', 'P=12347');

is(
   $exit_status,
   0,
   "Ignores slave1 when --check-slave-lag=slave2"
);

$row = $master_dbh->selectall_arrayref("select * from percona.checksums where db='sakila' and tbl='city'");
is(
   scalar @$row,
   1,
   "Checksummed table"
);

$slave1_dbh->do('START SLAVE sql_thread');
$slave2_dbh->do('STOP SLAVE');
$slave2_dbh->do('START SLAVE');
$sb->wait_for_slaves();

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
