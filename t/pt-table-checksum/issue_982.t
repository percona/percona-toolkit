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

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
if ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 8;
}

my $rows;
my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';
$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/checksum_tbl.sql');

# Normally checksum tbl is InnoDB but mk-table-checksum commits a txn
# for each chunk which is really slow.  Using MyISAM takes a minute off
# the runtime of this test.
$master_dbh->do("alter table test.checksum engine=myisam");

# #############################################################################
# Issue 982: --empty-replicate-table does not work with binlog-ignore-db
# #############################################################################

$master_dbh->do("insert into test.checksum (db,tbl,chunk) values ('db','tbl',0)");
sleep 1;

$rows = $slave_dbh->selectall_arrayref('select * from test.checksum');
is(
   scalar @$rows,
   1,
   "Slave checksum table has row"
);

$master_dbh->disconnect();
$slave_dbh->disconnect();

# Add a replication filter to the slave.
diag(`/tmp/12346/stop >/dev/null`);
diag(`/tmp/12345/stop >/dev/null`);
diag(`cp /tmp/12345/my.sandbox.cnf /tmp/12345/orig.cnf`);
diag(`echo "binlog-ignore-db=sakila" >> /tmp/12345/my.sandbox.cnf`);
diag(`echo "binlog-ignore-db=mysql"  >> /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
diag(`/tmp/12346/start >/dev/null`);

$output = output(
   sub { mk_table_checksum::main("F=$cnf", qw(--no-check-replication-filters),
      qw(--replicate=test.checksum -d mysql -t user --empty-replicate-table))
   },
   stderr => 1,
);

$master_dbh = $sb->get_dbh_for('master');
$slave_dbh  = $sb->get_dbh_for('slave1');

$rows = $slave_dbh->selectall_arrayref("select * from test.checksum where db='db'");
ok(
   @$rows == 0,
   "Slave checksum table deleted"
);

# Clear checksum table for next tests.
$master_dbh->do("truncate table test.checksum");
sleep 1;
$rows = $slave_dbh->selectall_arrayref("select * from test.checksum");
ok(
   !@$rows,
   "Checksum table empty on slave"
);

$master_dbh->disconnect();
$slave_dbh->disconnect();

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
$slave_dbh  = $sb->get_dbh_for('slave1');

$output = output(
   sub { mk_table_checksum::main("F=$cnf", qw(--no-check-replication-filters),
      qw(--replicate=test.checksum -d mysql -t user))
   },
   stderr => 1,
);

# Because we did not use --replicate-database, mk-table-checksum should
# have done USE mysql before updating the checksum table.  Thus, the
# checksums should show up on the slave.
sleep 1;
$rows = $slave_dbh->selectall_arrayref("select * from test.checksum where db='mysql' AND tbl='user'");
ok(
   @$rows == 1,
   "Checksum replicated with binlog-do-db, without --replicate-database"
);

# Now force --replicate-database test and the checksums should not replicate.

$master_dbh->do("use mysql");
$master_dbh->do("truncate table test.checksum");
sleep 1;
$rows = $slave_dbh->selectall_arrayref("select * from test.checksum");
ok(
   !@$rows,
   "Checksum table empty on slave"
);

$output = output(
   sub { mk_table_checksum::main("F=$cnf", qw(--no-check-replication-filters),
      qw(--replicate=test.checksum -d mysql -t user),
      qw(--replicate-database test))
   },
   stderr => 1,
);
sleep 1;
$rows = $slave_dbh->selectall_arrayref("select * from test.checksum where db='mysql' AND tbl='user'");
ok(
   !@$rows,
   "Checksum did not replicated with binlog-do-db, with --replicate-database"
);

# #############################################################################
# Restore original config.
# #############################################################################
$master_dbh->disconnect();
$slave_dbh->disconnect();

diag(`/tmp/12346/stop >/dev/null`);
diag(`/tmp/12345/stop >/dev/null`);
diag(`mv /tmp/12345/orig.cnf /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
diag(`/tmp/12346/start >/dev/null`);

$master_dbh = $sb->get_dbh_for('master');
$slave_dbh  = $sb->get_dbh_for('slave1');

# #############################################################################
# Test it again by looking at binlog to see that the db didn't change.
# #############################################################################
diag(`$trunk/sandbox/test-env reset`);
sleep 1;

# To speed this test up, ignore these tables.
# http://code.google.com/p/maatkit/issues/detail?id=1027
my $it = "payment,rental,help_topic,help_keyword,inventory,film_actor";

$output = output(
   sub { mk_table_checksum::main("F=$cnf",
      qw(--replicate=test.checksum), '--ignore-tables', $it, qw(--chunk-size 20k))
   },
   stderr => 1,
);
sleep 1;

my $row = $master_dbh->selectrow_hashref('show master status');
$output = `mysqlbinlog /tmp/12345/data/$row->{file} | grep 'use ' | sort -u`;
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
   sub { mk_table_checksum::main("F=$cnf", qw(--replicate-database test),
      qw(--replicate=test.checksum), '--ignore-tables', $it, qw(--chunk-size 20k))
   },
   stderr => 1,
);
sleep 1;

$row = $master_dbh->selectrow_hashref('show master status');
$output = `mysqlbinlog /tmp/12345/data/$row->{file} | grep 'use '`;
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
