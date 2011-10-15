#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More skip_all => 'Finish updating issue_982.t';

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
if ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 8;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3)); 
my $row;
my $output;

# #############################################################################
# Issue 982: --empty-replicate-table does not work with binlog-ignore-db
# #############################################################################

$sb->wipe_clean($master_dbh);
pt_table_checksum::main(@args, qw(-t sakila.country --quiet));
$master_dbh->do("insert into percona.checksums values ('sakila', 'country', 99, null, null, null, null, '', 0, '', 0, null)");
PerconaTest::wait_for_table($slave1_dbh, 'percona.checksums', "db='sakila' and tbl='country' and chunk=99");

$master_dbh->disconnect();
$slave1_dbh->disconnect();

# Add a replication filter to the slave.
diag(`/tmp/12346/stop >/dev/null`);
diag(`/tmp/12345/stop >/dev/null`);
diag(`cp /tmp/12345/my.sandbox.cnf /tmp/12345/orig.cnf`);
diag(`echo "binlog-ignore-db=sakila" >> /tmp/12345/my.sandbox.cnf`);
diag(`echo "binlog-ignore-db=mysql"  >> /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
diag(`/tmp/12346/start >/dev/null`);

$output = output(
   sub { pt_table_checksum::main(@args, qw(--no-check-replication-filters),
      qw(-d mysql -t user)) },
   stderr => 1,
);

$master_dbh = $sb->get_dbh_for('master');
$slave1_dbh = $sb->get_dbh_for('slave1');

$row = $slave1_dbh->selectall_arrayref("select * from percona.checksums where db='sakila' and tbl='country' and chunk=99");
ok(
   @$row == 0,
   "Slave checksum table deleted"
);

# Clear checksum table for next tests.
$master_dbh->do("truncate table percona.checksums");
wait_until(
   sub {
      $row = $slave1_dbh->selectall_arrayref("select * from percona.checksums");
      return !@$row;
   }
);

$master_dbh->disconnect();
$slave1_dbh->disconnect();

# Restore original config.
diag(`/tmp/12346/stop >/dev/null`);
diag(`/tmp/12345/stop >/dev/null`);
diag(`cp /tmp/12345/orig.cnf /tmp/12345/my.sandbox.cnf`);

# #############################################################################
# Test --replicate-database which resulted from this issue.
# #############################################################################

# Add a binlog-do-db filter so master will only replicate
# statements when USE mysql is in effect.
diag(`echo "binlog-do-db=mysql" >> /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
diag(`/tmp/12346/start >/dev/null`);

$master_dbh = $sb->get_dbh_for('master');
$slave1_dbh = $sb->get_dbh_for('slave1');

$output = output(
   sub { pt_table_checksum::main(@args, qw(--no-check-replication-filters),
      qw(--replicate=percona.checksums -d mysql -t user))
   },
   stderr => 1,
);

# Because we did not use --replicate-database, mk-table-checksum should
# have done USE mysql before updating the checksum table.  Thus, the
# checksums should show up on the slave.
sleep 1;
$row = $slave1_dbh->selectall_arrayref("select * from percona.checksums where db='mysql' AND tbl='user'");
ok(
   @$row == 1,
   "Checksum replicated with binlog-do-db, without --replicate-database"
);

# Now force --replicate-database test and the checksums should not replicate.

$master_dbh->do("use mysql");
$master_dbh->do("truncate table percona.checksums");
sleep 1;
$row = $slave1_dbh->selectall_arrayref("select * from percona.checksums");
ok(
   !@$row,
   "Checksum table empty on slave"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(--no-check-replication-filters),
      qw(--replicate=percona.checksums -d mysql -t user),
      qw(--replicate-database test))
   },
   stderr => 1,
);
sleep 1;
$row = $slave1_dbh->selectall_arrayref("select * from percona.checksums where db='mysql' AND tbl='user'");
ok(
   !@$row,
   "Checksum did not replicated with binlog-do-db, with --replicate-database"
);

# #############################################################################
# Restore original config.
# #############################################################################
$master_dbh->disconnect();
$slave1_dbh->disconnect();

diag(`/tmp/12346/stop >/dev/null`);
diag(`/tmp/12345/stop >/dev/null`);
diag(`mv /tmp/12345/orig.cnf /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
diag(`/tmp/12346/start >/dev/null`);

$master_dbh = $sb->get_dbh_for('master');
$slave1_dbh = $sb->get_dbh_for('slave1');

# #############################################################################
# Test it again by looking at binlog to see that the db didn't change.
# #############################################################################
diag(`$trunk/sandbox/test-env reset`);
sleep 1;

# To speed this test up, ignore these tables.
# http://code.google.com/p/maatkit/issues/detail?id=1027
my $it = "payment,rental,help_topic,help_keyword,inventory,film_actor";

$output = output(
   sub { pt_table_checksum::main(@args,
      qw(--replicate=percona.checksums), '--ignore-tables', $it, qw(--chunk-size 20k))
   },
   stderr => 1,
);
sleep 1;

$row = $master_dbh->selectrow_hashref('show master status');
$output = `$ENV{PERCONA_TOOLKIT_SANDBOX}/bin/mysqlbinlog /tmp/12345/data/$row->{file} | grep 'use ' | grep -v '^# Warning' |  sort -u`;
is(
   $output,
"use mysql/*!*/;
use sakila/*!*/;
use test/*!*/;
",
   "USE each table's db (binlog dump)"
);

diag(`$trunk/sandbox/test-env reset`);
sleep 1;

$output = output(
   sub { pt_table_checksum::main(@args, qw(--replicate-database test),
      qw(--replicate=percona.checksums), '--ignore-tables', $it, qw(--chunk-size 20k))
   },
   stderr => 1,
);
sleep 1;

$row = $master_dbh->selectrow_hashref('show master status');
$output = `$ENV{PERCONA_TOOLKIT_SANDBOX}/bin/mysqlbinlog /tmp/12345/data/$row->{file} | grep 'use ' | grep -v '^# Warning'`;
is(
   $output,
"use test/*!*/;
",
   "USE only --replicate-database db (binlog dump)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
