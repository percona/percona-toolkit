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
require "$trunk/bin/pt-slave-restart";

diag('Restarting the sandbox');
diag(`SAKILA=0 REPLICATION_THREADS=0 GTID=1 $trunk/sandbox/test-env restart`);
diag("Sandbox restarted");

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}

$source_dbh->do('DROP DATABASE IF EXISTS test');
$source_dbh->do('CREATE DATABASE test');
$source_dbh->do('CREATE TABLE test.t (a INT)');
$sb->wait_for_replicas;

# Bust replication
$replica_dbh->do('DROP TABLE test.t');
$source_dbh->do('INSERT INTO test.t SELECT 1');
wait_until(
   sub {
      my $row = $replica_dbh->selectrow_hashref("show ${replica_name} status");
      return $row->{last_sql_errno};
   }
);

my $r = $replica_dbh->selectrow_hashref("show ${replica_name} status");
like($r->{last_error}, qr/Table 'test.t' doesn't exist'/, 'It is busted');

# Start an instance
diag(`$trunk/bin/pt-slave-restart --max-sleep 0.25 -h 127.0.0.1 -P 12346 -u msandbox -p msandbox --daemonize --pid /tmp/pt-replica-restart.pid --log /tmp/pt-replica-restart.log`);
my $output = `ps x | grep 'pt-slave-restart \-\-max\-sleep ' | grep -v grep | grep -v pt-slave-restart.t`;
like($output, qr/pt-slave-restart --max/, 'It lives');

unlike($output, qr/Table 'test.t' doesn't exist'/, 'It is not busted');

ok(-f '/tmp/pt-replica-restart.pid', 'PID file created');
ok(-f '/tmp/pt-replica-restart.log', 'Log file created');

my ($pid) = $output =~ /^\s*(\d+)\s+/;
$output = `cat /tmp/pt-replica-restart.pid`;
chomp($output);
is($output, $pid, 'PID file has correct PID');

diag(`$trunk/bin/pt-slave-restart --stop -q`);
sleep 1;
$output = `ps -eaf | grep pt-slave-restart | grep -v grep`;
unlike($output, qr/pt-slave-restart --max/, 'It is dead');

diag(`rm -f /tmp/pt-replica-re*`);
ok(! -f '/tmp/pt-replica-restart.pid', 'PID file removed');

# #############################################################################
# Issue 118: pt-slave-restart --error-numbers option is broken
# #############################################################################
$output = `$trunk/bin/pt-slave-restart --stop --sentinel /tmp/pt-replica-restartup --error-numbers=1205,1317`;
like($output, qr{Successfully created file /tmp/pt-replica-restartup}, '--error-numbers works (issue 118)');

diag(`rm -f /tmp/pt-replica-re*`);

# #############################################################################
# Issue 459: mk-slave-restart --error-text is broken
# #############################################################################
# Bust replication again.  At this point, the source has test.t but
# the replica does not.
$source_dbh->do('DROP TABLE IF EXISTS test.t');
$source_dbh->do('CREATE TABLE test.t (a INT)');
sleep 1;
$replica_dbh->do('DROP TABLE test.t');
$source_dbh->do('INSERT INTO test.t SELECT 1');
$output = `/tmp/12346/use -e "show ${replica_name} status"`;
like(
   $output,
   qr/Table 'test.t' doesn't exist'/,
   'It is busted again'
);

# Start an instance
$output = `$trunk/bin/pt-slave-restart --max-sleep 0.25 -h 127.0.0.1 -P 12346 -u msandbox -p msandbox --error-text "doesn't exist" --run-time 1s 2>&1`;
unlike(
   $output,
   qr/Error does not match/,
   '--error-text works (issue 459)'
);

# #############################################################################
# Testing --recurse option
# #############################################################################
# Bust replication again.
$source_dbh->do('DROP TABLE IF EXISTS test.t');
$source_dbh->do('CREATE TABLE test.t (a INT)');
sleep 1;
$replica_dbh->do('DROP TABLE test.t');
$source_dbh->do('INSERT INTO test.t SELECT 1');
$output = `/tmp/12346/use -e "show ${replica_name} status"`;
like(
   $output,
   qr/Table 'test.t' doesn't exist'/,
   'It is busted again'
);

# Start an instance
$output = `$trunk/bin/pt-slave-restart --max-sleep 0.25 -h 127.0.0.1 -P 12345 -u msandbox -p msandbox --error-text "doesn't exist" --run-time 1s --recurse 1 2>&1`;

like(
   $output,
   qr/P=12346/,
   'Replica discovered'
);

$replica_dbh->do('CREATE TABLE test.t (a INT)');
$replica_dbh->do("start ${replica_name}");
$sb->wait_for_replicas;

# #############################################################################
# Testing --recurse option with --slave-user/--slave-password
# #############################################################################
# Create a new user that is going to be replicated on replicas.
if ($sandbox_version eq '8.0') {
    $sb->do_as_root("replica1", q/CREATE USER 'replica_user'@'localhost' IDENTIFIED WITH mysql_native_password BY 'replica_password'/);
} else {
    $sb->do_as_root("replica1", q/CREATE USER 'replica_user'@'localhost' IDENTIFIED BY 'replica_password'/);
}
$sb->do_as_root("replica1", q/GRANT REPLICATION CLIENT ON *.* TO 'replica_user'@'localhost'/);
$sb->do_as_root("replica1", q/GRANT REPLICATION SLAVE ON *.* TO 'replica_user'@'localhost'/);
$sb->do_as_root("replica1", q/FLUSH PRIVILEGES/);                

$sb->wait_for_replicas();

# Bust replication again.
$source_dbh->do('DROP TABLE IF EXISTS test.t');
$source_dbh->do('CREATE TABLE test.t (a INT)');
sleep 1;
$replica_dbh->do('DROP TABLE test.t');
$source_dbh->do('INSERT INTO test.t SELECT 1');
$output = `/tmp/12346/use -e "show ${replica_name} status"`;
like(
   $output,
   qr/Table 'test.t' doesn't exist'/,
   'It is busted again'
);

# Ensure we cannot connect to replicas using standard credentials
# Since replica2 is a replica of replica1, removing the user from the replica1 will remove
# the user also from replica2
$sb->do_as_root("replica1", q/RENAME USER 'msandbox'@'%' TO 'msandbox_old'@'%'/);
$sb->do_as_root("replica1", q/FLUSH PRIVILEGES/);
$sb->do_as_root("replica1", q/FLUSH TABLES/);

# Start an instance
$output = `$trunk/bin/pt-slave-restart --max-sleep 0.25 -h 127.0.0.1 -P 12345 -u msandbox -p msandbox --error-text "doesn't exist" --run-time 1s --recurse 1 --slave-user replica_user --slave-password replica_password 2>&1`;

like(
   $output,
   qr/P=12346/,
   'Replica discovered with --slave-user/--slave-password'
);

like(
   $output,
   qr/Option --slave-user is deprecated and will be removed in future versions./,
   'Deprecation warning printed when option --slave-user provided'
) or diag($output);

like(
   $output,
   qr/Option --slave-password is deprecated and will be removed in future versions./,
   'Deprecation warning printed when option --slave-password provided'
) or diag($output);

# Drop test user
$sb->do_as_root("replica1", q/DROP USER 'replica_user'@'localhost'/);
$sb->do_as_root("replica1", q/FLUSH PRIVILEGES/);

# Restore privilegs for the other tests
$sb->do_as_root("replica1", q/RENAME USER 'msandbox_old'@'%' TO 'msandbox'@'%'/);
$sb->do_as_root("source", q/FLUSH PRIVILEGES/);                
$sb->do_as_root("source", q/FLUSH TABLES/);

$replica_dbh->do('CREATE TABLE test.t (a INT)');
$replica_dbh->do("start ${replica_name}");
$sb->wait_for_replicas;

# ###########################################################################
# Issue 391: Add --pid option to all scripts
# ###########################################################################
`touch /tmp/pt-script.pid`;
$output = `$trunk/bin/pt-slave-restart --max-sleep 0.25 -h 127.0.0.1 -P 12346 -u msandbox -p msandbox s=1 --pid /tmp/pt-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/pt-script.pid exists},
   'Dies if PID file already exists (--pid without --daemonize) (issue 391)'
);
`rm -rf /tmp/pt-script.pid`;

# #############################################################################
# Issue 662: Option maxlength does not exist
# #############################################################################
my $ret = system("$trunk/bin/pt-slave-restart -h 127.0.0.1 -P 12346 -u msandbox -p msandbox --monitor --stop --max-sleep 1 --run-time 1 >/dev/null 2>&1");
is(
   $ret >> 8,
   0,
   "--monitor --stop doesn't cause error"
);

# #############################################################################
#  Issue 673: Use of uninitialized value in numeric gt (>)
# #############################################################################
$output = `$trunk/bin/pt-slave-restart --monitor  --error-numbers 1205,1317 --quiet -F /tmp/12346/my.sandbox.cnf  --run-time 1 2>&1`;
$output =~ s/pt-slave-restart is a link to pt-replica-restart.\nThis file name is deprecated and will be removed in future releases. Use pt-replica-restart instead.\n\n//;
is(
   $output,
   '',
   'No error with --quiet (issue 673)'
);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -f /tmp/pt-replica-re*`);
diag(`$trunk/sandbox/test-env restart`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
