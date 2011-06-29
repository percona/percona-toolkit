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
   plan tests => 3;
}

my $output;
my $row;
my $cnf  ='/tmp/12345/my.sandbox.cnf';
my @args = (qw(--replicate test.checksum  --empty-replicate-table -d test -t resume -q), '-F', $cnf, 'h=127.1', '--progress', 'time,1');

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

$slave1_dbh->do('stop slave sql_thread');
$row = $slave1_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'No',
   'Stopped slave SQL thread on slave1'
);

$slave2_dbh->do('stop slave sql_thread');
$row = $slave2_dbh->selectrow_hashref('show slave status');
is(
   $row->{slave_sql_running},
   'No',
   'Stopped slave SQL thread on slave2'
);

system("sleep 2 && /tmp/12346/use -e 'start slave sql_thread' >/dev/null 2>/dev/null &");
system("sleep 3 && /tmp/12347/use -e 'start slave sql_thread' >/dev/null 2>/dev/null &");

# This time we do not need to capture STDERR because mk-table-checksum
# should see slave2 come alive in 2 seconds then return before wait_for
# dies.
$output = output(
   sub { pt_table_checksum::main(@args); },
   stderr => 1,
);

like(
   $output,
   qr/Waiting for slave.+?Still waiting/s,
   "Progress reports while waiting for slaves"
);

# #############################################################################
# Done.
# #############################################################################
diag(`$trunk/sandbox/stop-sandbox remove 12347 >/dev/null`);
diag(`/tmp/12346/stop >/dev/null`);  # Start/stop clears SHOW SLAVE HOSTS.
diag(`/tmp/12346/start >/dev/null`);
$sb->wipe_clean($master_dbh);
diag(`$trunk/sandbox/test-env reset >/dev/null`);
exit;
