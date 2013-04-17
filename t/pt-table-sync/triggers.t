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
require "$trunk/bin/pt-table-sync";

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
elsif ( VersionParser->new($master_dbh) < '5.0.2' ) {
   plan skip_all => 'Sever does not support triggers (< 5.0.2)';
}
else {
   plan tests => 11;
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 37: mk-table-sync should warn about triggers
# #############################################################################
$sb->load_file('master', 't/pt-table-sync/samples/issue_37.sql');
$sb->use('master', '-e "SET SQL_LOG_BIN=0; INSERT INTO test.issue_37 VALUES (1), (2);"');

`$trunk/bin/pt-table-checksum h=127.0.0.1,P=12345,u=msandbox,p=msandbox --replicate test.checksum -d test --set-vars innodb_lock_wait_timeout=3 2>&1 > /dev/null`;

$output = `$trunk/bin/pt-table-sync --no-check-slave --execute u=msandbox,p=msandbox,h=127.0.0.1,P=12345,D=test,t=issue_37 h=127.1,P=12346 2>&1`;
like($output,
   qr/Triggers are defined/,
   'Die on trigger tbl write with one table (1/4, issue 37)'
);

$output = `$trunk/bin/pt-table-sync --replicate test.checksum --sync-to-master --execute h=127.1,P=12346,u=msandbox,p=msandbox -d test -t issue_37 2>&1`;
like($output,
   qr/Triggers are defined/,
   'Die on trigger tbl write with --replicate --sync-to-master (2/4, issue 37)'
);

$output = `$trunk/bin/pt-table-sync --replicate test.checksum --execute h=127.1,P=12345,u=msandbox,p=msandbox -d test -t issue_37 2>&1`;
like(
   $output,
   qr/Triggers are defined/,
   'Die on trigger tbl write with --replicate (3/4, issue 37)'
);

$output = `$trunk/bin/pt-table-sync --execute --ignore-databases mysql h=127.0.0.1,P=12345,u=msandbox,p=msandbox h=127.1,P=12346 2>&1`;
like(
   $output,
   qr/Triggers are defined/,
   'Die on trigger tbl write with no opts (4/4, issue 37)'
);

$output = `/tmp/12346/use -D test -e 'SELECT * FROM issue_37'`;
ok(
   !$output,
   'Table with trigger was not written'
);

$output = `$trunk/bin/pt-table-sync --no-check-slave --execute u=msandbox,p=msandbox,h=127.0.0.1,P=12345,D=test,t=issue_37 h=127.1,P=12346 --no-check-triggers 2>&1`;
unlike(
   $output,
   qr/Triggers are defined/,
   'Writes to tbl with trigger with --no-check-triggers (issue 37)'
);

$output = `/tmp/12346/use -D test -e 'SELECT * FROM issue_37'`;
like(
   $output, qr/a.+1.+2/ms,
   'Table with trigger was written'
);

# #############################################################################
#  Issue 367: mk-table-sync incorrectly advises --ignore-triggers
# #############################################################################

diag('Loading file and waiting for replication');
$sb->load_file('master', 't/pt-table-sync/samples/issue_367.sql');

# Make slave db1.t1 and db2.t1 differ from master.
$slave_dbh->do('INSERT INTO db1.t1 VALUES (9)');
$slave_dbh->do('DELETE FROM db2.t1 WHERE i > 4');

# Replicate checksum of db2.t1.
$output = `$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox --replicate db1.checksum --create-replicate-table --databases db1,db2 --set-vars innodb_lock_wait_timeout=3 2>&1`;
like(
   $output,
   qr/db2.t1/,
   'Replicated checksums (issue 367)'
);

# Sync db2, which has no triggers, between master and slave using
# --replicate which has entries for both db1 and db2.  db1 has a
# trigger but since we also specify --databases db2, then db1 should
# be ignored.
$output = `$trunk/bin/pt-table-sync h=127.1,P=12345,u=msandbox,p=msandbox  --databases db2 --replicate db1.checksum --execute 2>&1`;
unlike(
   $output,
   qr/Cannot write to table with triggers/,
   "Doesn't warn about trigger on db1 (issue 367)"
);

$sb->wait_for_slaves();
my $r = $slave_dbh->selectrow_array('SELECT * FROM db2.t1 WHERE i = 5');
is(
   $r,
   '5',
   'Syncs db2, ignores db1 with trigger (issue 367)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
