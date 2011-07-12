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
my $vp = new VersionParser();
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

# Reset master and slave relay logs so the second slave
# starts faster (i.e. so it doesn't have to replay the
# masters logs which is stuff from previous tests that we
# don't care about).
diag(`$trunk/sandbox/test-env reset >/dev/null`);

# It's not really master1, we just use its port 12348.
# diag(`/tmp/12348/stop >/dev/null 2>&1`);
# diag(`rm -rf /tmp/12348/ >/dev/null 2>&1`);
diag(`$trunk/sandbox/start-sandbox slave 12348 12345 >/dev/null`);
my $dbh3 = $sb->get_dbh_for('master1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$dbh3 ) {
   plan skip_all => 'Cannot connect to second sandbox slave';
}
else {
   plan tests => 4;
}

$sb->wipe_clean($master_dbh);

# #############################################################################
# Issue 533: mk-table-sync does not work with replicate-do-db
# #############################################################################

# This slave is new so it doesn't have the dbs and tbls
# created above.  We create some so that the current db
# will change as they get checked.  It should stop at
# something other than onlythisdb.  Since SHOW DATABSES
# returns sorted, test should be checked after onlythisdb.
$master_dbh->do('DROP DATABASE IF EXISTS test');
$master_dbh->do('CREATE DATABASE test');
$master_dbh->do('CREATE TABLE test.foo (i INT, UNIQUE INDEX (i))');
$master_dbh->do('INSERT INTO test.foo VALUES (1),(2),(9)');
diag(`/tmp/12345/use < $trunk/t/pt-table-sync/samples/issue_533.sql`);

# My box acts weird so I double check that this is ok.
my $r;
my $i = 0;
PerconaTest::wait_until(
   sub {
      eval {
         $r = $dbh3->selectrow_arrayref('SHOW TABLES FROM test');
      };
      return 1 if ($r->[0] || '') eq 'foo';
      return 0;
   },
   0.5,
   30,
);
is_deeply(
   $r,
   ['foo'],
   'Slave has other db.tbl'
) or die "Timeout waiting for slave";

# Stop the slave, add replicate-do-db to its config, and restart it.
$dbh3->disconnect();
diag(`/tmp/12348/stop >/dev/null`);
diag(`echo "replicate-do-db = onlythisdb" >> /tmp/12348/my.sandbox.cnf`);
diag(`/tmp/12348/start >/dev/null`);
$dbh3 = $sb->get_dbh_for('master1');

die "Second sandbox master lost test.foo"
   unless -f '/tmp/12348/data/test/foo.frm';

# Make master and slave differ.  Because we USE test, this DELETE on
# the master won't replicate to the slave now that replicate-do-db
# is set.
$master_dbh->do('USE test');
$master_dbh->do('DELETE FROM onlythisdb.t WHERE i = 2');
$dbh3->do('INSERT INTO test.foo VALUES (5)');

$r = $dbh3->selectall_arrayref('SELECT * FROM onlythisdb.t ORDER BY i');
is_deeply(
   $r,
   [[1],[2],[3]],
   'do-replicate-db is out of sync before sync'
);

`$trunk/bin/pt-table-sync h=127.1,P=12348,u=msandbox,p=msandbox --sync-to-master --execute --no-check-triggers --ignore-databases sakila,mysql 2>&1`;

$r = $dbh3->selectall_arrayref('SELECT * FROM onlythisdb.t ORDER BY i');
is_deeply(
   $r,
   [[1],[3]],
   'do-replicate-db is in sync after sync'
);

$r = $dbh3->selectall_arrayref('SELECT * FROM test.foo');
is_deeply(
   $r,
   [[1],[2],[5],[9]],
   'db not allowed by do-replicate-db was not synced'
);

$dbh3->disconnect();
diag(`$trunk/sandbox/stop-sandbox remove 12348 >/dev/null`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
