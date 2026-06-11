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

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
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
   plan tests => 9;
}

# #############################################################################
# Maatkit issue 533: mk-table-sync needs to work with replicate-do-db. It should
# do a USE <db> as it moves through the tables. We test this by setting
# replicate-do-db=test1, and then making sure that changes in the test1 database
# get replicated, but test2 doesn't.
# #############################################################################

# Add two new test databases with a simple table. IMPORTANT: we do this before
# reconfiguring the server, so this gets replicated!
foreach my $db (qw(test1 test2)) {
   $source_dbh->do("DROP DATABASE IF EXISTS $db");
   $source_dbh->do("CREATE DATABASE $db");
   $source_dbh->do("CREATE TABLE $db.foo (i INT NOT NULL PRIMARY KEY)");
   $source_dbh->do("INSERT INTO $db.foo VALUES (1),(2),(9)");
}

$sb->wait_for_replicas();

# Stop replica 12346, add replicate-do-db to its config, and restart it.
$replica1_dbh->disconnect;
diag('Restarting replica 12346 with replicate-do-db=test1');
diag(`/tmp/12346/stop >/dev/null`);
diag(`echo "replicate-do-db = test1" >> /tmp/12346/my.sandbox.cnf`);
diag(`/tmp/12346/start >/dev/null`);
$replica1_dbh = $sb->get_dbh_for('replica1');
$replica2_dbh->do("stop ${replica_name}");
$replica2_dbh->do("start ${replica_name}");

my $r = $replica1_dbh->selectrow_hashref("show ${replica_name} status");
is($r->{replicate_do_db}, 'test1', 'Server reconfigured');

# #############################################################################
# IMPORTANT: anything you want to replicate must now USE test1 first!
# IMPORTANT: $sb->wait_for_replicas won't work now!
# #############################################################################

# Make source and replica differ.  Because we USE test2, this DELETE on
# the source won't replicate to the replica in either case.
$source_dbh->do("USE test2");
$source_dbh->do("DELETE FROM test1.foo WHERE i = 2");
$source_dbh->do("DELETE FROM test2.foo WHERE i = 2");
$source_dbh->do("COMMIT");

# NOTE: $sb->wait_for_replicas() won't work! Hence we do our own way...
$source_dbh->do('USE test1');
$source_dbh->do('INSERT INTO test1.foo(i) VALUES(10)');
PerconaTest::wait_for_table($replica2_dbh, "test1.foo", "i=10");

# Prove that the replica (12347, not 12346) still has i=2 in test2.foo, and the
# source doesn't. That is, both test1 and test2 are out-of-sync on the replica.
$r = $source_dbh->selectall_arrayref('select * from test1.foo where i=2');
is_deeply( $r, [], 'source has no test1.foo.i=2');
$r = $source_dbh->selectall_arrayref('select * from test2.foo where i=2');
is_deeply( $r, [], 'source has no test2.foo.i=2');
$r = $replica2_dbh->selectall_arrayref('select * from test1.foo where i=2');
is_deeply( $r, [[2]], 'replica2 has test1.foo.i=2');
$r = $replica2_dbh->selectall_arrayref('select * from test2.foo where i=2'),
is_deeply( $r, [[2]], 'replica2 has test2.foo.i=2') or diag(`/tmp/12346/use -e "show ${replica_name} status\\G"; /tmp/12347/use -e "show ${replica_name} status\\G"`);

# Now we sync, and if pt-table-sync USE's the db it's syncing, then test1 should
# be in sync afterwards, and test2 shouldn't.

my $procs = $source_dbh->selectcol_arrayref('show processlist');
diag('MySQL processes on source: ', join(', ', @$procs));

my $output = output(
   sub { pt_table_sync::main("h=127.1,P=12346,u=msandbox,p=msandbox",
      qw(--sync-to-source --execute --no-check-triggers),
      "--databases", "test1,test2") },
   stderr => 1,
);

# NOTE: $sb->wait_for_replicas() won't work! Hence we do our own way...
$source_dbh->do('USE test1');
$source_dbh->do('INSERT INTO test1.foo(i) VALUES(11)');
PerconaTest::wait_for_table($replica2_dbh, "test1.foo", "i=11");

$procs = $source_dbh->selectcol_arrayref('show processlist');
diag('MySQL processes on source: ', join(', ', @$procs));

$r = $replica2_dbh->selectall_arrayref('select * from test1.foo where i=2');
is_deeply( $r, [], 'replica2 has NO test1.foo.i=2 after sync');
$r = $replica2_dbh->selectall_arrayref('select * from test2.foo where i=2'),
is_deeply( $r, [[2]], 'replica2 has test2.foo.i=2 after sync') or diag(`/tmp/12346/use -e "show ${replica_name} status\\G"; /tmp/12347/use -e "show ${replica_name} status\\G"`);

$replica1_dbh->disconnect;
diag('Reconfiguring instance 12346 without replication filters');
diag(`grep -v replicate.do.db /tmp/12346/my.sandbox.cnf > /tmp/new.cnf`);
diag(`mv /tmp/new.cnf /tmp/12346/my.sandbox.cnf`);
diag(`/tmp/12346/stop >/dev/null`);
diag(`/tmp/12346/start >/dev/null`);
$replica2_dbh->do("stop ${replica_name}");
$replica2_dbh->do("start ${replica_name}");

$replica1_dbh = $sb->get_dbh_for('replica1');
$r = $replica1_dbh->selectrow_hashref("show ${replica_name} status");
is($r->{replicate_do_db}, '', 'Replication filter removed');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
