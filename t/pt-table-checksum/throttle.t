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

use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

diag(`$trunk/sandbox/test-env reset`);
diag(`$trunk/sandbox/stop-sandbox remove 12347 >/dev/null`);
diag(`$trunk/sandbox/start-sandbox slave 12347 12346 >/dev/null`);

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
   plan tests => 21;
}

my $output;
my $row;
my $cnf  ='/tmp/12345/my.sandbox.cnf';
my @args = (qw(--replicate test.checksum  --empty-replicate-table -d test -t resume -q), '-F', $cnf, 'h=127.1');

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/checksum_tbl.sql');
# We're not using resume table for anything specific, we just need
# any table to checksum.
$sb->load_file('master', 't/pt-table-checksum/samples/resume.sql');

wait_until(  # slaves aren't lagging
   sub {
      $row = $slave1_dbh->selectrow_hashref('show slave status');
      return 0 if $row->{Seconds_Behind_Master};
      $row = $slave2_dbh->selectrow_hashref('show slave status');
      return 0 if $row->{Seconds_Behind_Master};
      return 1;
   }, 0.5, 10);

mk_table_checksum::main(@args);

$row = $master_dbh->selectall_arrayref('select * from test.checksum');
is(
   scalar @$row,
   1,
   'Throttle slavelag, no slave lag'
);

# By default --throttle-method should find all slaves and wait for the most
# lagged one.  If we stop slave sql_thread on slave2, mk-table-checksum
# should see this (as undef lag) and wait.  While it's waiting, no
# checksum should appear in the repl table.
$slave2_dbh->do('stop slave sql_thread');
$row = $slave2_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'No',
   'Stopped slave SQL thread on slave2'
);

# wait_for() is going to die() when its alarm goes off, and mk-table-checksum
# is going to catch this and complain.  We can ignore it.
{
   local *STDERR;
   open  STDERR, ">/dev/null"
      or die "Cannot redirect STDERR to /dev/null: $OS_ERROR";
   wait_for(sub { mk_table_checksum::main(@args); }, 2);
}

$row = $master_dbh->selectall_arrayref('select * from test.checksum');
is(
   scalar @$row,
   0,
   'Throttle slavelag waited for slave2'
);

$slave2_dbh->do('start slave sql_thread');
$row = $slave2_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'Yes',
   'Started slave SQL thread on slave2'
) or BAIL_OUT("Failed to restart SQL thread on slave2 (12347)");

# Repeat the test but this time re-enable slave2 while mk-table-checksum
# is waiting and it should checksum the table.
$slave2_dbh->do('stop slave sql_thread');
$row = $slave2_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'No',
   'Stopped slave SQL thread on slave2'
);

system("sleep 2 && /tmp/12347/use -e 'start slave sql_thread' >/dev/null 2>/dev/null &");

# This time we do not need to capture STDERR because mk-table-checksum
# should see slave2 come alive in 2 seconds then return before wait_for
# dies.
wait_for(sub { mk_table_checksum::main(@args); }, 5);

$row = $master_dbh->selectall_arrayref('select * from test.checksum');
is(
   scalar @$row,
   1,
   'Throttle slavelag waited for slave2 and continue when it was ready'
);


# #############################################################################
# --check-slave-lag
# #############################################################################

# Before --throttle-method this stuff was handled by --check-slave-lag which
# specifies one slave.  Because Ryan flogs me severely when I break
# backwards compatibility, specifying --check-slave-lag limits --throttle-method
# to that one slave.  To check this we stop slave sql_thread on slave2
# and specify slave1.  The checksum should proceed because slave2 should
# be ignored.

$slave2_dbh->do('stop slave sql_thread');
$row = $slave2_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'No',
   'Stopped slave SQL thread on slave2'
);

wait_for(sub { mk_table_checksum::main(@args, qw(--check-slave-lag P=12346)); }, 2);

$row = $master_dbh->selectall_arrayref('select * from test.checksum');
is(
   scalar @$row,
   1,
   'Throttle slavelag checked only --check-slave-lag'
);

# Start slave2 sql_thread and stop slave1 sql_thread and test that
# mk-table-checksum is really checking and waiting for just --slave-lag-dbh.
$slave2_dbh->do('start slave sql_thread');
$row = $slave2_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'Yes',
   'Started slave SQL thread on slave2'
) or BAIL_OUT("Failed to restart SQL thread on slave2 (12347)");

$slave1_dbh->do('stop slave sql_thread');
$row = $slave1_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'No',
   'Stopped slave SQL thread on slave1'
);

{
   local *STDERR;
   open  STDERR, ">/dev/null"
      or die "Cannot redirect STDERR to /dev/null: $OS_ERROR";
   wait_for(sub { mk_table_checksum::main(@args, qw(--check-slave-lag P=12346)); }, 2);
}

$row = $master_dbh->selectall_arrayref('select * from test.checksum');
is(
   scalar @$row,
   0,
   'Throttle slavelag waited for --check-slave-lag'
);


$slave1_dbh->do('start slave sql_thread');
$row = $slave1_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'Yes',
   'Started slave SQL thread on slave1'
) or BAIL_OUT("Failed to restart SQL thread on slave1 (12346)");

# Clear out all checksum tables before next test where we'll stop slaves
# and test throttle method "none".
$master_dbh->do('TRUNCATE TABLE test.checksum');
sleep 1;

$slave1_dbh->do('stop slave sql_thread');
$row = $slave1_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'No',
   'Stopped slave SQL thread on slave1'
);

# Disable throttle explicitly.

$slave2_dbh->do('stop slave sql_thread');
$row = $slave2_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'No',
   'Stopped slave SQL thread on slave2'
);

# All slaves are stopped at this point.
wait_for(sub { mk_table_checksum::main(@args, qw(--throttle-method none)) }, 2);

$row = $master_dbh->selectall_arrayref('select * from test.checksum');
is(
   scalar @$row,
   1,
   'Throttle none'
);

$row = $slave1_dbh->selectall_arrayref('select * from test.checksum');
is(
   scalar @$row,
   0,
   'No checksum replicated to slave1 yet'
);

$row = $slave2_dbh->selectall_arrayref('select * from test.checksum');
is(
   scalar @$row,
   0,
   'No checksum replicated to slave2 yet'
);


$slave1_dbh->do('start slave sql_thread');
$row = $slave1_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'Yes',
   'Started slave SQL thread on slave1'
) or BAIL_OUT("Failed to restart SQL thread on slave1 (12346)");

$slave2_dbh->do('start slave sql_thread');
$row = $slave2_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'Yes',
   'Started slave SQL thread on slave2'
) or BAIL_OUT("Failed to restart SQL thread on slave2 (12347)");

sleep 1;

$row = $slave1_dbh->selectall_arrayref('select * from test.checksum');
is(
   scalar @$row,
   1,
   'Checksum replicated to slave1'
);

$row = $slave2_dbh->selectall_arrayref('select * from test.checksum');
is(
   scalar @$row,
   1,
   'Checksum replicated to slave2'
);

# #############################################################################
# Done.
# #############################################################################
diag(`$trunk/sandbox/stop-sandbox remove 12347 >/dev/null`);
$sb->wipe_clean($master_dbh);
diag(`$trunk/sandbox/test-env reset >/dev/null`);
exit;
