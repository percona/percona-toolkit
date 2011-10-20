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
# so we need to specify --lock-wait-timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3), '--max-load', '');
my $output;
my $row;
my $exit_status;

wait_until(  # slaves aren't lagging
   sub {
      $row = $slave1_dbh->selectrow_hashref('show slave status');
      return 0 if $row->{Seconds_Behind_Master};
      $row = $slave2_dbh->selectrow_hashref('show slave status');
      return 0 if $row->{Seconds_Behind_Master};
      return 1;
   }
) or die "Slaves are still lagging";

# ############################################################################
# --check-slave-lag
# ############################################################################

$slave1_dbh->do('stop slave sql_thread');
$row = $slave1_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'No',
   'Stopped slave SQL thread on slave1'
);

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

# Start slave2 sql_thread and stop slave1 sql_thread and test that
# mk-table-checksum is really checking and waiting for just --slave-lag-dbh.
$slave1_dbh->do('start slave sql_thread');
$row = $slave1_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'Yes',
   'Started slave SQL thread on slave1'
) or BAIL_OUT("Failed to restart SQL thread on slave2 (12347)");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
