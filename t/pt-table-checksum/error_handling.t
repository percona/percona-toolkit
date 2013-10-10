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

$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my $output;
my $exit_status;

$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 81: put some data that's too big into the boundaries table
# #############################################################################
$sb->load_file('master', 't/pt-table-checksum/samples/checksum_tbl_truncated.sql');

$output = output(
   sub { pt_table_checksum::main(@args,
      qw(--replicate test.truncated_checksums -t sakila.film_category),
      qw(--chunk-time 0 --chunk-size 100) ) },
   stderr => 1,
);

like(
   $output,
   qr/MySQL error 1265: Data truncated/,
   "MySQL error 1265: Data truncated for column"
);

my (@errors) = $output =~ m/error/;
is(
   scalar @errors,
   1,
   "Only one warning for MySQL error 1265"
);

# ############################################################################
# Lock wait timeout
# ############################################################################
$master_dbh->do('use sakila');
$master_dbh->do('begin');
$master_dbh->do('select * from city for update');

$output = output(
   sub { $exit_status = pt_table_checksum::main(@args, qw(-t sakila.city)) },
   stderr => 1,
);

my $original_output;
($output, $original_output) = PerconaTest::normalize_checksum_results($output);

like(
   $original_output,
   qr/Lock wait timeout exceeded/,
   "Warns about lock wait timeout"
);

like(
   $output,
   qr/^0 0 0 1 1 sakila.city/m,
   "Skips chunk that times out"
);

is(
   $exit_status,
   32,
   "Exit 32 (SKIP_CHUNK)"
);

# Lock wait timeout for sandbox servers is 3s, so sleep 4 then commit
# to release the lock.  That should allow the checksum query to finish.
my ($id) = $master_dbh->selectrow_array('select connection_id()');
system("sleep 4 ; /tmp/12345/use -e 'KILL $id' >/dev/null");

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t sakila.city)) },
   stderr => 1,
   trf    => sub { return PerconaTest::normalize_checksum_results(@_) },
);

unlike(
   $output,
   qr/Lock wait timeout exceeded/,
   "Lock wait timeout retried"
);

like(
   $output,
   qr/^0 0 600 1 0 sakila.city/m,
   "Checksum retried after lock wait timeout"
);

# Reconnect to master since we just killed ourself.
$master_dbh = $sb->get_dbh_for('master');

# #############################################################################
# pt-table-checksum breaks replication if a slave table is missing or different
# https://bugs.launchpad.net/percona-toolkit/+bug/1009510
# #############################################################################

# Just re-using this simple table.
$sb->load_file('master', "t/pt-table-checksum/samples/600cities.sql");

$master_dbh->do("SET SQL_LOG_BIN=0");
$master_dbh->do("ALTER TABLE test.t ADD COLUMN col3 int");
$master_dbh->do("SET SQL_LOG_BIN=1");

$output = output(
   sub { $exit_status = pt_table_checksum::main(@args,
      qw(-t test.t)) },
   stderr => 1,
);

like(
   $output,
   qr/Skipping table test.t/,
   "Skip table missing column on slave (bug 1009510)"
);

like(
   $output,
   qr/replica h=127.0.0.1,P=12346 is missing these columns: col3/,
   "Checked slave1 (bug 1009510)"
);

like(
   $output,
   qr/replica h=127.0.0.1,P=12347 is missing these columns: col3/,
   "Checked slave2 (bug 1009510)"
);

is(
   $exit_status,
   64,  # SKIP_TABLE
   "Non-zero exit status (bug 1009510)"
);

$output = output(
   sub { $exit_status = pt_table_checksum::main(@args,
      qw(-t test.t), '--columns', 'id,city') },
   stderr => 1,
);

unlike(
   $output,
   qr/Skipping table test.t/,
   "Doesn't skip table missing column on slave with --columns (bug 1009510)"
);

is(
   $exit_status,
   0,
   "Zero exit status with --columns (bug 1009510)"
);

# Use the --replicate table created by the previous ^ tests.

# Create a user that can't create the --replicate table.
diag(`/tmp/12345/use -uroot -pmsandbox < $trunk/t/lib/samples/ro-checksum-user.sql 2>&1`);
diag(`/tmp/12345/use -uroot -pmsandbox -e "GRANT REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO ro_checksum_user\@'%'" 2>&1`);

# Remove the --replicate table from slave1 and slave2,
# so it's only on the master...
$slave1_dbh->do("DROP DATABASE percona");
$sb->wait_for_slaves;

$output = output(
   sub { $exit_status = pt_table_checksum::main(
      "h=127.1,u=ro_checksum_user,p=msandbox,P=12345",
      qw(--set-vars innodb_lock_wait_timeout=3 -t mysql.user)) },
   stderr => 1,
);

like(
   $output,
   qr/database percona exists on the master/,
   "CREATE DATABASE error and db is missing on slaves (bug 1039569)"
);

diag(`/tmp/12345/use -uroot -pmsandbox -e "DROP USER ro_checksum_user\@'%'" 2>&1`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
