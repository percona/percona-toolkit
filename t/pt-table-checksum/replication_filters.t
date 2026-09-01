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
#   plan skip_all => "pt-table-checksum/replication_filters.t is a top 5 slowest file; set SLOW_TESTS=1 to enable it.";
#}


# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific replica hosts, but
# the sandbox servers are all on one host so all replicas have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

use Data::Dumper;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $sb_version = VersionParser->new($source_dbh);
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
   plan tests => 12;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox,s=1';
my @args       = ($source_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', '');
my $output;
my $row;

my ($orig_binlog_format_source) = $source_dbh->selectrow_array(q{SELECT @@global.binlog_format});
my ($orig_binlog_format_replica1) = $replica1_dbh->selectrow_array(q{SELECT @@global.binlog_format});
my ($orig_binlog_format_replica2) = $replica2_dbh->selectrow_array(q{SELECT @@global.binlog_format});

$source_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$source_dbh->do("SET binlog_format = 'STATEMENT'");

# You must call this sub if the source 12345 or replica1 12346 is restarted,
# else a replica might notice that its source went away and enter the "trying
# to reconnect" state, and then replication will break as the tests continue.
sub restart_replica_threads {
   $replica1_dbh->do("STOP ${replica_name}");
   $replica2_dbh->do("STOP ${replica_name}");
   $replica1_dbh->do("START ${replica_name}");
   $replica2_dbh->do("START ${replica_name}");
}

# #############################################################################
# Repl filters on all replicas, at all depths, should be found.
# #############################################################################

# Add a replication filter to the replicas.
diag('Stopping 12346 and 12347 to reconfigure them with replication filters');
diag(`/tmp/12347/stop >/dev/null`);
diag(`/tmp/12346/stop >/dev/null`);
for my $port ( qw(12346 12347) ) {
   diag(`cp /tmp/$port/my.sandbox.cnf /tmp/$port/orig.cnf`);
   diag(`echo "replicate-ignore-db=foo" >> /tmp/$port/my.sandbox.cnf`);
   diag(`/tmp/$port/start >/dev/null`);
}
$replica1_dbh = $sb->get_dbh_for('replica1');
$replica2_dbh = $sb->get_dbh_for('replica2');

$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$replica1_dbh->do("SET binlog_format = 'STATEMENT'");
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("STOP ${replica_name}");
$replica2_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$replica2_dbh->do("SET binlog_format = 'STATEMENT'");
$replica2_dbh->do("START ${replica_name}");

my $pos = PerconaTest::get_source_binlog_pos($source_dbh);

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t sakila.country)) },
   stderr => 1,
);

is(
   PerconaTest::get_source_binlog_pos($source_dbh),
   $pos,
   "Did not checksum with replication filter"
) or diag($output);

like(
   $output,
   qr/h=127.0.0.1,P=12346/,
   "Warns about replication filter on replica1"
);

like(
   $output,
   qr/h=127.0.0.1,P=12347/,
   "Warns about replication filter on replica2"
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
   PerconaTest::get_source_binlog_pos($source_dbh),
   '>',
   $pos,
   "Did checksum with replication filter"
);

# Remove the replication filter from the replica.
diag('Restarting the replicas again to remove the replication filters');
diag(`/tmp/12347/stop >/dev/null`);
diag(`/tmp/12346/stop >/dev/null`);
for my $port ( qw(12346 12347) ) {
   diag(`mv /tmp/$port/orig.cnf /tmp/$port/my.sandbox.cnf`);
   diag(`/tmp/$port/start >/dev/null`);
}
$replica1_dbh = $sb->get_dbh_for('replica1');
$replica2_dbh = $sb->get_dbh_for('replica2');

$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$replica1_dbh->do("SET binlog_format = 'STATEMENT'");
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("STOP ${replica_name}");
$replica2_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$replica2_dbh->do("SET binlog_format = 'STATEMENT'");
$replica2_dbh->do("START ${replica_name}");

# #############################################################################
# Issue 982: --empty-replicate-table does not work with binlog-ignore-db
# #############################################################################

# Write some results to source and replica for dbs mysql and sakila.
$sb->wipe_clean($source_dbh);
$output = output(
   sub {
      pt_table_checksum::main(@args, qw(--chunk-time 0 --chunk-size 100),
         '-t', 'mysql.user,sakila.city', qw(--quiet));
   },
   stderr => 1,
);
PerconaTest::wait_for_table($replica1_dbh, 'percona.checksums', "db='sakila' and tbl='city' and chunk=6");

# Add a replication filter to the source: ignore db mysql.
$source_dbh->disconnect();
diag('Restarting 12345 to add binlog_ignore_db filter');
diag(`/tmp/12345/stop >/dev/null`);
diag(`cp /tmp/12345/my.sandbox.cnf /tmp/12345/orig.cnf`);
diag(`echo "binlog-ignore-db=mysql" >> /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
restart_replica_threads();
$source_dbh = $sb->get_dbh_for('source');

$source_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$source_dbh->do("SET binlog_format = 'STATEMENT'");

# Checksum the tables again in 1 chunk.  Since db percona isn't being
# ignored, deleting old results in the repl table should replicate.
# But since db mysql is ignored, the new results for mysql.user should
# not replicate.
pt_table_checksum::main(@args, qw(--no-check-replication-filters),
   '-t', 'mysql.user,sakila.city', qw(--quiet --no-replicate-check),
   qw(--chunk-size 1000));

PerconaTest::wait_for_table($replica1_dbh, 'percona.checksums', "db='sakila' and tbl='city' and chunk=1");

$row = $replica1_dbh->selectall_arrayref("select db,tbl,chunk from percona.checksums order by db,tbl,chunk");
is_deeply(
   $row,
   [[qw(sakila city 1)]],
   "binlog-ignore-db and --empty-replicate-table"
) or print STDERR Dumper($row);

$source_dbh->do("use percona");
$source_dbh->do("truncate table percona.checksums");
wait_until(
   sub {
      $row=$replica1_dbh->selectall_arrayref("select * from percona.checksums");
      return !@$row;
   }
);

# #############################################################################
# Test --replicate-database which resulted from this issue.
# #############################################################################

# Restore original config.  Then add a binlog-do-db filter so source
# will only replicate statements when USE mysql is in effect.
$source_dbh->disconnect();
diag('Restarting source to reconfigure with binlog-do-db filter only');
diag(`/tmp/12345/stop >/dev/null`);
diag(`cp /tmp/12345/orig.cnf /tmp/12345/my.sandbox.cnf`);
diag(`echo "binlog-do-db=mysql" >> /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
$source_dbh = $sb->get_dbh_for('source');
restart_replica_threads();

$source_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$source_dbh->do("SET binlog_format = 'STATEMENT'");

$output = output(
   sub { pt_table_checksum::main(@args, qw(--no-check-replication-filters),
      qw(-d mysql -t user))
   },
   stderr => 1,
);

# Because we did not use --replicate-database, pt-table-checksum should
# have done USE mysql before updating the repl table.  Thus, the
# checksums should show up on the replica.
PerconaTest::wait_for_table($replica1_dbh, 'percona.checksums', "db='mysql' and tbl='user' and chunk=1");

$row = $replica1_dbh->selectall_arrayref("select db,tbl,chunk from percona.checksums order by db,tbl,chunk");
is_deeply(
   $row,
   [[qw(mysql user 1)]],
   "binlog-do-do, without --replicate-database"
) or print STDERR Dumper($row);

# Now force --replicate-database sakila and the checksums should not replicate.
$source_dbh->do("use mysql");
$source_dbh->do("truncate table percona.checksums");
wait_until(
   sub {
      $row=$replica1_dbh->selectall_arrayref("select * from percona.checksums");
      return !@$row;
   }
);

$pos = PerconaTest::get_source_binlog_pos($source_dbh);

pt_table_checksum::main(@args, qw(--quiet --no-check-replication-filters),
  qw(-t mysql.user --replicate-database sakila --no-replicate-check));

my $pos_after = PerconaTest::get_source_binlog_pos($source_dbh);
wait_until(
   sub {
      $pos_after <= PerconaTest::get_replica_pos_relative_to_source($replica1_dbh);
   }
);

$row = $replica1_dbh->selectall_arrayref("select * from percona.checksums where db='mysql' AND tbl='user'");
ok(
   !@$row,
   "binlog-do-db, with --replicate-database"
) or print STDERR Dumper($row);

is(
   PerconaTest::get_source_binlog_pos($source_dbh),
   $pos,
   "Source pos did not change"
);

# #############################################################################
# Check that only the expected dbs are used.
# #############################################################################
# Get the source's binlog pos so we can check its binlogs for USE statements
$row = $source_dbh->selectrow_hashref("show ${source_status} status");

if ( $sandbox_version ge '8.4' ) {
   $replica1_dbh->do("STOP REPLICA");
   $replica1_dbh->do("CHANGE REPLICATION FILTER replicate_ignore_db=() ");
   $replica1_dbh->do("START REPLICA");
   $replica2_dbh->do("STOP REPLICA");
   $replica2_dbh->do("CHANGE REPLICATION FILTER replicate_ignore_db=() ");
   $replica1_dbh->do("START REPLICA");
}

# Restore the original config.
diag('Restoring original sandbox server configuration');
$source_dbh->disconnect();
diag(`/tmp/12345/stop >/dev/null`);
diag(`mv /tmp/12345/orig.cnf /tmp/12345/my.sandbox.cnf`);
diag(`/tmp/12345/start >/dev/null`);
# Restart the replicas so they reconnect immediately.
restart_replica_threads();
$source_dbh = $sb->get_dbh_for('source');

$source_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$source_dbh->do("SET binlog_format = 'STATEMENT'");

# Get the source's binlog pos so we can check its binlogs for USE statements
$row = $source_dbh->selectrow_hashref("show ${source_status} status");

pt_table_checksum::main(@args, qw(--quiet));

my $mysqlbinlog;
if ( -x "$ENV{PERCONA_TOOLKIT_SANDBOX}/bin/mysqlbinlog" ) {
   $mysqlbinlog = "$ENV{PERCONA_TOOLKIT_SANDBOX}/bin/mysqlbinlog";
} elsif ( $mysqlbinlog = `which mysqlbinlog` ) {
   chomp $mysqlbinlog;
}

$output = `$mysqlbinlog /tmp/12345/data/$row->{file} --start-position=$row->{position} | grep 'use ' | grep -v '^# Warning' | grep -v 'pseudo_replica_mode' | LOCALE=en_US.utf8 LANG=en_US.UTF-8 sort -u | sed -e 's/\`//g'`;

my $use_dbs = "use mysql/*!*/;
use percona/*!*/;
use percona_test/*!*/;
use sakila/*!*/;
";

if ($sb_version >= '5.7') {
   $use_dbs .= "use sys/*!*/;\n";
}

is(
   $output,
   $use_dbs,
   "USE each table's database (binlog dump)"
);

# Get the source's binlog pos so we can check its binlogs for USE statements
$row = $source_dbh->selectrow_hashref("show ${source_status} status");

pt_table_checksum::main(@args, qw(--quiet --replicate-database percona));

$output = `$mysqlbinlog /tmp/12345/data/$row->{file} --start-position=$row->{position} | grep 'use ' | grep -v '^# Warning' | grep -v 'pseudo_replica_mode' | LOCALE=en_US.utf8 LANG=en_US.UTF-8 sort -u | sed -e 's/\`//g'`;

is(
   $output,
   "use percona/*!*/;\n",
   "USE only --replicate-database (binlog dump)"
);

# #############################################################################
# Done.
# #############################################################################
$source_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format_source}'");
$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format_replica1}'");
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("STOP ${replica_name}");
$replica2_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format_replica2}'");
$replica2_dbh->do("START ${replica_name}");
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
