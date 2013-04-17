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
   $master_dbh->do("DROP DATABASE IF EXISTS $db");
   $master_dbh->do("CREATE DATABASE $db");
   $master_dbh->do("CREATE TABLE $db.foo (i INT NOT NULL PRIMARY KEY)");
   $master_dbh->do("INSERT INTO $db.foo VALUES (1),(2),(9)");
}

$sb->wait_for_slaves();

# Stop slave 12346, add replicate-do-db to its config, and restart it.
$slave1_dbh->disconnect;
diag('Restarting slave 12346 with replicate-do-db=test1');
diag(`/tmp/12346/stop >/dev/null`);
diag(`echo "replicate-do-db = test1" >> /tmp/12346/my.sandbox.cnf`);
diag(`/tmp/12346/start >/dev/null`);
$slave1_dbh = $sb->get_dbh_for('slave1');
$slave2_dbh->do("stop slave");
$slave2_dbh->do("start slave");

my $r = $slave1_dbh->selectrow_hashref('show slave status');
is($r->{replicate_do_db}, 'test1', 'Server reconfigured');

# #############################################################################
# IMPORTANT: anything you want to replicate must now USE test1 first!
# IMPORTANT: $sb->wait_for_slaves won't work now!
# #############################################################################

# Make master and slave differ.  Because we USE test2, this DELETE on
# the master won't replicate to the slave in either case.
$master_dbh->do("USE test2");
$master_dbh->do("DELETE FROM test1.foo WHERE i = 2");
$master_dbh->do("DELETE FROM test2.foo WHERE i = 2");
$master_dbh->do("COMMIT");

# NOTE: $sb->wait_for_slaves() won't work! Hence we do our own way...
$master_dbh->do('USE test1');
$master_dbh->do('INSERT INTO test1.foo(i) VALUES(10)');
PerconaTest::wait_for_table($slave2_dbh, "test1.foo", "i=10");

# Prove that the slave (12347, not 12346) still has i=2 in test2.foo, and the
# master doesn't. That is, both test1 and test2 are out-of-sync on the slave.
$r = $master_dbh->selectall_arrayref('select * from test1.foo where i=2');
is_deeply( $r, [], 'master has no test1.foo.i=2');
$r = $master_dbh->selectall_arrayref('select * from test2.foo where i=2');
is_deeply( $r, [], 'master has no test2.foo.i=2');
$r = $slave2_dbh->selectall_arrayref('select * from test1.foo where i=2');
is_deeply( $r, [[2]], 'slave2 has test1.foo.i=2');
$r = $slave2_dbh->selectall_arrayref('select * from test2.foo where i=2'),
is_deeply( $r, [[2]], 'slave2 has test2.foo.i=2') or diag(`/tmp/12346/use -e "show slave status\\G"; /tmp/12347/use -e "show slave status\\G"`);

# Now we sync, and if pt-table-sync USE's the db it's syncing, then test1 should
# be in sync afterwards, and test2 shouldn't.

my $procs = $master_dbh->selectcol_arrayref('show processlist');
diag('MySQL processes on master: ', join(', ', @$procs));

my $output = output(
   sub { pt_table_sync::main("h=127.1,P=12346,u=msandbox,p=msandbox",
      qw(--sync-to-master --execute --no-check-triggers),
      "--databases", "test1,test2") },
   stderr => 1,
);

# NOTE: $sb->wait_for_slaves() won't work! Hence we do our own way...
$master_dbh->do('USE test1');
$master_dbh->do('INSERT INTO test1.foo(i) VALUES(11)');
PerconaTest::wait_for_table($slave2_dbh, "test1.foo", "i=11");

$procs = $master_dbh->selectcol_arrayref('show processlist');
diag('MySQL processes on master: ', join(', ', @$procs));

$r = $slave2_dbh->selectall_arrayref('select * from test1.foo where i=2');
is_deeply( $r, [], 'slave2 has NO test1.foo.i=2 after sync');
$r = $slave2_dbh->selectall_arrayref('select * from test2.foo where i=2'),
is_deeply( $r, [[2]], 'slave2 has test2.foo.i=2 after sync') or diag(`/tmp/12346/use -e "show slave status\\G"; /tmp/12347/use -e "show slave status\\G"`);

$slave1_dbh->disconnect;
diag('Reconfiguring instance 12346 without replication filters');
diag(`grep -v replicate.do.db /tmp/12346/my.sandbox.cnf > /tmp/new.cnf`);
diag(`mv /tmp/new.cnf /tmp/12346/my.sandbox.cnf`);
diag(`/tmp/12346/stop >/dev/null`);
diag(`/tmp/12346/start >/dev/null`);
$slave2_dbh->do("stop slave");
$slave2_dbh->do("start slave");

$slave1_dbh = $sb->get_dbh_for('slave1');
$r = $slave1_dbh->selectrow_hashref('show slave status');
is($r->{replicate_do_db}, '', 'Replication filter removed');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
