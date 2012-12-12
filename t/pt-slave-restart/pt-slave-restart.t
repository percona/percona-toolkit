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

$master_dbh->do('DROP DATABASE IF EXISTS test');
$master_dbh->do('CREATE DATABASE test');
$master_dbh->do('CREATE TABLE test.t (a INT)');
$sb->wait_for_slaves;

# Bust replication
$slave_dbh->do('DROP TABLE test.t');
$master_dbh->do('INSERT INTO test.t SELECT 1');
wait_until(
   sub {
      my $row = $slave_dbh->selectrow_hashref('show slave status');
      return $row->{last_sql_errno};
   }
);

my $r = $slave_dbh->selectrow_hashref('show slave status');
like($r->{last_error}, qr/Table 'test.t' doesn't exist'/, 'It is busted');

# Start an instance
diag(`$trunk/bin/pt-slave-restart --max-sleep .25 -h 127.0.0.1 -P 12346 -u msandbox -p msandbox --daemonize --pid /tmp/pt-slave-restart.pid --log /tmp/pt-slave-restart.log`);
my $output = `ps x | grep 'pt-slave-restart \-\-max\-sleep ' | grep -v grep | grep -v pt-slave-restart.t`;
like($output, qr/pt-slave-restart --max/, 'It lives');

unlike($output, qr/Table 'test.t' doesn't exist'/, 'It is not busted');

ok(-f '/tmp/pt-slave-restart.pid', 'PID file created');
ok(-f '/tmp/pt-slave-restart.log', 'Log file created');

my ($pid) = $output =~ /^\s*(\d+)\s+/;
$output = `cat /tmp/pt-slave-restart.pid`;
is($output, $pid, 'PID file has correct PID');

diag(`$trunk/bin/pt-slave-restart --stop -q`);
sleep 1;
$output = `ps -eaf | grep pt-slave-restart | grep -v grep`;
unlike($output, qr/pt-slave-restart --max/, 'It is dead');

diag(`rm -f /tmp/pt-slave-re*`);
ok(! -f '/tmp/pt-slave-restart.pid', 'PID file removed');

# #############################################################################
# Issue 118: pt-slave-restart --error-numbers option is broken
# #############################################################################
$output = `$trunk/bin/pt-slave-restart --stop --sentinel /tmp/pt-slave-restartup --error-numbers=1205,1317`;
like($output, qr{Successfully created file /tmp/pt-slave-restartup}, '--error-numbers works (issue 118)');

diag(`rm -f /tmp/pt-slave-re*`);

# #############################################################################
# Issue 459: mk-slave-restart --error-text is broken
# #############################################################################
# Bust replication again.  At this point, the master has test.t but
# the slave does not.
$master_dbh->do('DROP TABLE IF EXISTS test.t');
$master_dbh->do('CREATE TABLE test.t (a INT)');
sleep 1;
$slave_dbh->do('DROP TABLE test.t');
$master_dbh->do('INSERT INTO test.t SELECT 1');
$output = `/tmp/12346/use -e 'show slave status'`;
like(
   $output,
   qr/Table 'test.t' doesn't exist'/,
   'It is busted again'
);

# Start an instance
$output = `$trunk/bin/pt-slave-restart --max-sleep .25 -h 127.0.0.1 -P 12346 -u msandbox -p msandbox --error-text "doesn't exist" --run-time 1s 2>&1`;
unlike(
   $output,
   qr/Error does not match/,
   '--error-text works (issue 459)'
);

# ###########################################################################
# Issue 391: Add --pid option to all scripts
# ###########################################################################
`touch /tmp/pt-script.pid`;
$output = `$trunk/bin/pt-slave-restart --max-sleep .25 -h 127.0.0.1 -P 12346 -u msandbox -p msandbox --pid /tmp/pt-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/pt-script.pid already exists},
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
is(
   $output,
   '',
   'No error with --quiet (issue 673)'
);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -f /tmp/pt-slave-re*`);
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
