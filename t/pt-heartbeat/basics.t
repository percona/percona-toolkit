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
use Data::Dumper;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-heartbeat";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}

$sb->create_dbs($master_dbh, ['test']);

my $output;
my $cnf       = '/tmp/12345/my.sandbox.cnf';
my $cmd       = "$trunk/bin/pt-heartbeat -F $cnf ";
my $pid_file  = "/tmp/__pt-heartbeat-test.pid";
my $sent_file = "/tmp/pt-heartbeat-sentinel";
my $ps_grep_cmd = "ps x | grep pt-heartbeat | grep daemonize | grep -v grep";

diag(`rm $sent_file 2>/dev/null`);

$master_dbh->do('drop table if exists test.heartbeat');
$master_dbh->do(q{CREATE TABLE test.heartbeat (
             id int NOT NULL PRIMARY KEY,
             ts datetime NOT NULL
          ) ENGINE=MEMORY});
$sb->wait_for_slaves;

# Issue: pt-heartbeat should check that the heartbeat table has a row
$output = output(
   sub { pt_heartbeat::main('-F', $cnf,
      qw(-D test --check --no-insert-heartbeat-row)) },
   stderr => 1,
);
like(
   $output,
   qr/heartbeat table is empty/ms,
   'Dies on empty heartbeat table with --check (issue 45)'
);

$output = output(
   sub { pt_heartbeat::main('-F', $cnf,
      qw(-D test --monitor --run-time 1s --no-insert-heartbeat-row)) },
   stderr => 1,
);
like(
   $output,
   qr/heartbeat table is empty/ms,
   'Dies on empty heartbeat table with --monitor (issue 45)'
);

$output = output(
   sub { pt_heartbeat::main('-F', $cnf, qw(-D test --check)) },
);
my $row = $master_dbh->selectall_hashref('select * from test.heartbeat', 'id');
is(
   $row->{1}->{id},
   1,
   "Automatically inserts heartbeat row (issue 1292)"
);

# Run one instance with --replace to create the table.
output(
   sub { pt_heartbeat::main('-F', $cnf,
      qw(-D test --update --replace --run-time 1s)) },
   stderr => 1,
);
ok(
   $master_dbh->selectrow_array('select id from test.heartbeat'),
   'Record is there'
);

# Check the delay and ensure it is only a single line with nothing but the
# delay (no leading whitespace or anything).
output(
   sub { pt_heartbeat::main('-F', $cnf, qw(-D test --check)) },
   stderr => 1,
);
chomp $output;
like($output, qr/^\d+$/, 'Output is just a number');

# Start one daemonized instance to update it
system("$cmd --daemonize -D test --update --run-time 3s --pid $pid_file 1>/dev/null 2>/dev/null");
PerconaTest::wait_for_files($pid_file);
$output = `$ps_grep_cmd`;
like($output, qr/$cmd/, 'It is running');
ok(-f $pid_file, 'PID file created');
my ($pid) = $output =~ /^\s*(\d+)\s+/;
$output = `cat $pid_file` if -f $pid_file;
is($output, $pid, 'PID file has correct PID');

$output = `$cmd -D test --monitor --run-time 1s`;
if ( $output ) {
   chomp ($output);
   $output =~ s/\d/0/g;
}
is(
   $output,
   '   0s [  0.00s,  0.00s,  0.00s ]',
   'It is being updated',
);
PerconaTest::wait_until(sub { !-f $pid_file });

$output = `$ps_grep_cmd`;
chomp $output;
unlike($output, qr/$cmd/, 'It is not running anymore');
ok(! -f $pid_file, 'PID file removed');

# Run again, create the sentinel, and check that the sentinel makes the
# daemon quit.
system("$cmd --daemonize -D test --update 1>/dev/null 2>/dev/null");
$output = `$ps_grep_cmd`;
like($output, qr/$cmd/, 'It is running');
$output = `$cmd -D test --stop`;
like($output, qr/Successfully created/, 'Created sentinel');
sleep(2);
$output = `$ps_grep_cmd`;
unlike($output, qr/$cmd/, 'It is not running');
ok(-f $sent_file, 'Sentinel file is there');
unlink($sent_file);
$master_dbh->do('drop table if exists test.heartbeat'); # This will kill it

# #############################################################################
# Issue 353: Add --create-table to mk-heartbeat
# #############################################################################

# These creates the new table format, whereas the preceding tests used the
# old format, so tests from here on may need --master-server-id.

$master_dbh->do('drop table if exists test.heartbeat');
$sb->wait_for_slaves;

$output = output(
   sub { pt_heartbeat::main('-F', $cnf,
      qw(--update --run-time 1s --database test --table heartbeat),
      qw(--create-table)) },
   stderr => 1,
);
$master_dbh->do('use test');
$row = $master_dbh->selectcol_arrayref("SHOW TABLES LIKE 'heartbeat'");
is(
   $row->[0],
   'heartbeat', 
   '--create-table creates heartbeat table'
) or diag($output, Dumper($row));

# #############################################################################
# Issue 352: Add port to mk-heartbeat --check output
# #############################################################################
sleep 1;
$output = output(
   sub { pt_heartbeat::main(
      qw(--host 127.1 --user msandbox --password msandbox --port 12345),
      qw(-D test --check --recurse 1 --master-server-id 12345)) },
   stderr => 1,
);
like(
   $output,
   qr/:12346\s+\d/,
   '--check output has :port'
);

# #############################################################################
# Bug 1004567: pt-heartbeat --update --replace causes duplicate key error
# #############################################################################

# Create the heartbeat table on the master and slave.
$master_dbh->do("DROP TABLE IF EXISTS test.heartbeat");
$sb->wait_for_slaves();

$output = output(
   sub { pt_heartbeat::main("F=/tmp/12345/my.sandbox.cnf",
      qw(-D test --update --replace --create-table --run-time 1))
   }
);

$row = $master_dbh->selectrow_arrayref('SELECT server_id FROM test.heartbeat');
is(
   $row->[0],
   '12345',
   'Heartbeat on master'
);

$sb->wait_for_slaves();

$row = $slave1_dbh->selectrow_arrayref('SELECT server_id FROM test.heartbeat');
is(
   $row->[0],
   '12345',
   'Heartbeat on slave1'
);

# Drop the heartbeat table only on the master.
$master_dbh->do("SET SQL_LOG_BIN=0");
$master_dbh->do("DROP TABLE test.heartbeat");
$master_dbh->do("SET SQL_LOG_BIN=1");

# Re-create the heartbeat table on the master.
$output = output(
   sub { pt_heartbeat::main("F=/tmp/12345/my.sandbox.cnf",
      qw(-D test --update --replace --create-table --run-time 1))
   }
);

$row = $master_dbh->selectrow_arrayref('SELECT server_id FROM test.heartbeat');
is(
   $row->[0],
   '12345',
   'New heartbeat on master'
);

$sb->wait_for_slaves();

$row = $slave1_dbh->selectrow_hashref("SHOW SLAVE STATUS");
is(
   $row->{last_error},
   '',
   "No slave error"
);

# #############################################################################
# --check-read-only
# #############################################################################

diag(`/tmp/12345/use -u root -e "GRANT ALL ON *.* TO 'bob'\@'%' IDENTIFIED BY 'msandbox'"`);
diag(`/tmp/12345/use -u root -e "REVOKE SUPER ON *.* FROM 'bob'\@'%'"`);

$output = output(
   sub { pt_heartbeat::main("u=bob,F=/tmp/12346/my.sandbox.cnf",
      qw(-D test --update --replace --run-time 1))
   },
   stderr => 1
);

like(
   $output,
   qr/--read-only/,
   "By default, fails if the server is read_only=1"
);

$output = output(
   sub { pt_heartbeat::main("u=bob,F=/tmp/12346/my.sandbox.cnf",
      qw(-D test --update --replace --run-time 1 --check-read-only))
   },
   stderr => 1
);

unlike(
   $output,
   qr/--read-only/,
   "...but just skips doing any work and waits if --check-read-only was specified"
);

diag(`/tmp/12345/use -u root -e "DROP USER 'bob'\@'%'"`);

# #############################################################################
# Done.
# #############################################################################
diag(`rm $pid_file $sent_file 2>/dev/null`);
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
