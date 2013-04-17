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
   plan skip_all => "pt-table-checksum/replication_filters.t is a top 5 slowest file; set SLOW_TESTS=1 to enable it.";
}


# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

use Data::Dumper;

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
   plan tests => 12;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', '');
my $output;
my $row;

# You must call this sub if the master 12345 or slave1 12346 is restarted,
# else a slave might notice that its master went away and enter the "trying
# to reconnect" state, and then replication will break as the tests continue.
sub restart_slave_threads {
   $slave1_dbh->do('STOP SLAVE');
   $slave2_dbh->do('STOP SLAVE');
   $slave1_dbh->do('START SLAVE');
   $slave2_dbh->do('START SLAVE');
}

# #############################################################################
# Repl filters on all slaves, at all depths, should be found.
# #############################################################################

# Add a replication filter to the slaves.
diag('Stopping 12346 and 12347 to reconfigure them with replication filters');
diag(`/tmp/12347/stop >/dev/null`);
diag(`/tmp/12346/stop >/dev/null`);
for my $port ( qw(12346 12347) ) {
   diag(`cp /tmp/$port/my.sandbox.cnf /tmp/$port/orig.cnf`);
   diag(`echo "replicate-ignore-db=foo" >> /tmp/$port/my.sandbox.cnf`);
   diag(`/tmp/$port/start >/dev/null`);
}
$slave1_dbh = $sb->get_dbh_for('slave1');
$slave2_dbh = $sb->get_dbh_for('slave2');

my $pos = PerconaTest::get_master_binlog_pos($master_dbh);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t sakila.country)) },
   stderr => 1,
);

is(
   PerconaTest::get_master_binlog_pos($master_dbh),
   $pos,
   "Did not checksum with replication filter"
);

like(
   $output,
   qr/h=127.0.0.1,P=12346/,
   "Warns about replication filter on slave1"
);

like(
   $output,
   qr/h=127.0.0.1,P=12347/,
   "Warns about replication filter on slave2"
);

# Disable the check and run again
$output = output(
   sub { pt_table_checksum::main(@args, qw(-t sakila.country),
      qw(--no-check-replication-filters)) },
   stderr => 1,
);

like(
   $output,
   qr/sakila\.country$/,
   "--no-check-replication-filters didn't cause warning, and the tool ran"
);

cmp_ok(
   PerconaTest::get_master_binlog_pos($master_dbh),
   '>',
   $pos,
   "Did checksum with replication filter"
);

# Remove the replication filter from the slave.
diag('Restarting the slaves again to remove the replication filters');
diag(`/tmp/12347/stop >/dev/null`);
diag(`/tmp/12346/stop >/dev/null`);
for my $port ( qw(12346 12347) ) {
   diag(`mv /tmp/$port/orig.cnf /tmp/$port/my.sandbox.cnf`);
   diag(`/tmp/$port/start >/dev/null`);
}
$slave1_dbh = $sb->get_dbh_for('slave1');
$slave2_dbh = $sb->get_dbh_for('slave2');

# #############################################################################
# Issue 982: --empty-replicate-table does not work with binlog-ignore-db
# #############################################################################

# Write some results to master and slave for dbs mysql and sakila.
$sb->wipe_clean($master_dbh);
$output = output(
   sub {
      pt_table_checksum::main(@args, qw(--chunk-time 0 --chunk-size 100),
         '-t', 'mysql.user,sakila.city', qw(--quiet));
   },
   stderr => 1,
);
PerconaTest::wait_for_table($slave1_dbh, 'percona.checksums', "db='sakila' and tbl='city' and chunk=6");

# Add a replication filter to the master: ignore db mysql.
$master_dbh->disconnect();
diag('Restarting 12345 to add binlog_ignore_db filter');
diag(`/tmp/12345/stop >/dev/null`);
diag(`cp /tmp/12345/my.sandbox.cnf /tmp/12345/orig.cnf`);
diag(`echo "binlog-ignore-db=mysql" >> /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
restart_slave_threads();
$master_dbh = $sb->get_dbh_for('master');

# Checksum the tables again in 1 chunk.  Since db percona isn't being
# ignored, deleting old results in the repl table should replicate.
# But since db mysql is ignored, the new results for mysql.user should
# not replicate.
pt_table_checksum::main(@args, qw(--no-check-replication-filters),
   '-t', 'mysql.user,sakila.city', qw(--quiet --no-replicate-check),
   qw(--chunk-size 1000));

PerconaTest::wait_for_table($slave1_dbh, 'percona.checksums', "db='sakila' and tbl='city' and chunk=1");

$row = $slave1_dbh->selectall_arrayref("select db,tbl,chunk from percona.checksums order by db,tbl,chunk");
is_deeply(
   $row,
   [[qw(sakila city 1)]],
   "binlog-ignore-db and --empty-replicate-table"
) or print STDERR Dumper($row);

$master_dbh->do("use percona");
$master_dbh->do("truncate table percona.checksums");
wait_until(
   sub {
      $row=$slave1_dbh->selectall_arrayref("select * from percona.checksums");
      return !@$row;
   }
);

# #############################################################################
# Test --replicate-database which resulted from this issue.
# #############################################################################

# Restore original config.  Then add a binlog-do-db filter so master
# will only replicate statements when USE mysql is in effect.
$master_dbh->disconnect();
diag('Restarting master to reconfigure with binlog-do-db filter only');
diag(`/tmp/12345/stop >/dev/null`);
diag(`cp /tmp/12345/orig.cnf /tmp/12345/my.sandbox.cnf`);
diag(`echo "binlog-do-db=mysql" >> /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
$master_dbh = $sb->get_dbh_for('master');
restart_slave_threads();

$output = output(
   sub { pt_table_checksum::main(@args, qw(--no-check-replication-filters),
      qw(-d mysql -t user))
   },
   stderr => 1,
);

# Because we did not use --replicate-database, pt-table-checksum should
# have done USE mysql before updating the repl table.  Thus, the
# checksums should show up on the slave.
PerconaTest::wait_for_table($slave1_dbh, 'percona.checksums', "db='mysql' and tbl='user' and chunk=1");

$row = $slave1_dbh->selectall_arrayref("select db,tbl,chunk from percona.checksums order by db,tbl,chunk");
is_deeply(
   $row,
   [[qw(mysql user 1)]],
   "binlog-do-do, without --replicate-database"
) or print STDERR Dumper($row);

# Now force --replicate-database sakila and the checksums should not replicate.
$master_dbh->do("use mysql");
$master_dbh->do("truncate table percona.checksums");
wait_until(
   sub {
      $row=$slave1_dbh->selectall_arrayref("select * from percona.checksums");
      return !@$row;
   }
);

$pos = PerconaTest::get_master_binlog_pos($master_dbh);

pt_table_checksum::main(@args, qw(--quiet --no-check-replication-filters),
  qw(-t mysql.user --replicate-database sakila --no-replicate-check));

my $pos_after = PerconaTest::get_master_binlog_pos($master_dbh);
wait_until(
   sub {
      $pos_after <= PerconaTest::get_slave_pos_relative_to_master($slave1_dbh);
   }
);

$row = $slave1_dbh->selectall_arrayref("select * from percona.checksums where db='mysql' AND tbl='user'");
ok(
   !@$row,
   "binlog-do-db, with --replicate-database"
) or print STDERR Dumper($row);

is(
   PerconaTest::get_master_binlog_pos($master_dbh),
   $pos,
   "Master pos did not change"
);

# #############################################################################
# Check that only the expected dbs are used.
# #############################################################################

# Restore the original config.
diag('Restoring original sandbox server configuration');
$master_dbh->disconnect();
diag(`/tmp/12345/stop >/dev/null`);
diag(`mv /tmp/12345/orig.cnf /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
# Restart the slaves so they reconnect immediately.
restart_slave_threads();
$master_dbh = $sb->get_dbh_for('master');

# Get the master's binlog pos so we can check its binlogs for USE statements
$row = $master_dbh->selectrow_hashref('show master status');

pt_table_checksum::main(@args, qw(--quiet));
my $mysqlbinlog = `which mysqlbinlog`;
if ( $mysqlbinlog ) {
   chomp $mysqlbinlog;
}
elsif ( -x "$ENV{PERCONA_TOOLKIT_SANDBOX}/bin/mysqlbinlog" ) {
   $mysqlbinlog = "$ENV{PERCONA_TOOLKIT_SANDBOX}/bin/mysqlbinlog";
}

$output = `$mysqlbinlog /tmp/12345/data/$row->{file} --start-position=$row->{position} | grep 'use ' | grep -v '^# Warning' |  sort -u | sed -e 's/\`//g'`;

my $use_dbs = "use mysql/*!*/;
use percona/*!*/;
use percona_test/*!*/;
use sakila/*!*/;
";

is(
   $output,
   $use_dbs,
   "USE each table's database (binlog dump)"
);

# Get the master's binlog pos so we can check its binlogs for USE statements
$row = $master_dbh->selectrow_hashref('show master status');

pt_table_checksum::main(@args, qw(--quiet --replicate-database percona));

$output = `$mysqlbinlog /tmp/12345/data/$row->{file} --start-position=$row->{position} | grep 'use ' | grep -v '^# Warning' | sort -u | sed -e 's/\`//g'`;

is(
   $output,
   "use percona/*!*/;\n",
   "USE only --replicate-database (binlog dump)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
