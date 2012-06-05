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

# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
shift @INC;  # our unshift (above)
shift @INC;  # PerconaTest's unshift
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
   plan tests => 11;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3), '--max-load', '');
my $output;
my $row;

# You must call this sub if the master 12345 or slave1 12346 is restarted,
# else a slave might notice that its master went away and enter the "trying
# to reconnect" state, and then replication will break as the tests continue.
sub reset_slaves {
   $slave1_dbh->do('STOP SLAVE');
   $slave2_dbh->do('STOP SLAVE');
   $slave1_dbh->do('START SLAVE');
   $slave2_dbh->do('START SLAVE');
}

# #############################################################################
# Repl filters on all slaves, at all depths, should be found.
# #############################################################################

# Add a replication filter to the slaves.
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
   "Warns about replication fitler on slave1"
);

like(
   $output,
   qr/h=127.0.0.1,P=12347/,
   "Warns about replication fitler on slave2"
);

# Disable the check.
$output = output(
   sub { pt_table_checksum::main(@args, qw(-t sakila.country),
      qw(--no-check-replication-filters)) },
   stderr => 1,
);

like(
   $output,
   qr/sakila\.country$/,
   "--no-check-replication-filters"
);

# Remove the replication filter from the slave.
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
pt_table_checksum::main(@args, qw(--chunk-time 0 --chunk-size 100),
   '-t', 'mysql.user,sakila.city', qw(--quiet));
PerconaTest::wait_for_table($slave1_dbh, 'percona.checksums', "db='sakila' and tbl='city' and chunk=6");

# Add a replication filter to the master: ignore db mysql.
$master_dbh->disconnect();
diag(`/tmp/12345/stop >/dev/null`);
diag(`cp /tmp/12345/my.sandbox.cnf /tmp/12345/orig.cnf`);
diag(`echo "binlog-ignore-db=mysql" >> /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
reset_slaves();
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
   "binlog-ignore-db"
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
diag(`/tmp/12345/stop >/dev/null`);
diag(`cp /tmp/12345/orig.cnf /tmp/12345/my.sandbox.cnf`);
diag(`echo "binlog-do-db=mysql" >> /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
$master_dbh = $sb->get_dbh_for('master');
reset_slaves();

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

# Now force --replicate-database test and the checksums should not replicate.
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

sleep 1;

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
$master_dbh->disconnect();
diag(`/tmp/12345/stop >/dev/null`);
diag(`mv /tmp/12345/orig.cnf /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
$master_dbh = $sb->get_dbh_for('master');

# Reset the slaves and clear the binlogs.
diag(`$trunk/sandbox/test-env reset`);

pt_table_checksum::main(@args, qw(--quiet));

$row = $master_dbh->selectrow_hashref('show master status');
$output = `$ENV{PERCONA_TOOLKIT_SANDBOX}/bin/mysqlbinlog /tmp/12345/data/$row->{file} | grep 'use ' | grep -v '^# Warning' |  sort -u`;

is(
   $output,
"use mysql/*!*/;
use percona/*!*/;
use percona_test/*!*/;
use sakila/*!*/;
",
   "USE each table's database (binlog dump)"
);

# Clear the binlogs.
diag(`$trunk/sandbox/test-env reset`);

pt_table_checksum::main(@args, qw(--quiet --replicate-database percona));

$output = `$ENV{PERCONA_TOOLKIT_SANDBOX}/bin/mysqlbinlog /tmp/12345/data/$row->{file} | grep 'use ' | grep -v '^# Warning'`;
is(
   $output,
"use percona/*!*/;
",
   "USE only --replicate-database (binlog dump)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
