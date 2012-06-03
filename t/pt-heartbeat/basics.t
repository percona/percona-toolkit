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
require "$trunk/bin/pt-heartbeat";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 18;
}

$sb->create_dbs($dbh, ['test']);

my $output;
my $cnf       = '/tmp/12345/my.sandbox.cnf';
my $cmd       = "$trunk/bin/pt-heartbeat -F $cnf ";
my $pid_file  = "/tmp/__pt-heartbeat-test.pid";
my $sent_file = "/tmp/pt-heartbeat-sentinel";
my $ps_grep_cmd = "ps x | grep pt-heartbeat | grep daemonize | grep -v grep";

`rm $sent_file 2>/dev/null`;

$dbh->do('drop table if exists test.heartbeat');
$dbh->do(q{CREATE TABLE test.heartbeat (
             id int NOT NULL PRIMARY KEY,
             ts datetime NOT NULL
          ) ENGINE=MEMORY});

# Issue: pt-heartbeat should check that the heartbeat table has a row
$output = `$cmd -D test --check --no-insert-heartbeat-row 2>&1`;
like($output, qr/heartbeat table is empty/ms, 'Dies on empty heartbeat table with --check (issue 45)');

$output = `$cmd -D test --monitor --run-time 1s --no-insert-heartbeat-row 2>&1`;
like($output, qr/heartbeat table is empty/ms, 'Dies on empty heartbeat table with --monitor (issue 45)');

$output = output(
   sub { pt_heartbeat::main('-F', $cnf, qw(-D test --check)) },
);
my $row = $dbh->selectall_hashref('select * from test.heartbeat', 'id');
is(
   $row->{1}->{id},
   1,
   "Automatically inserts heartbeat row (issue 1292)"
);

# Run one instance with --replace to create the table.
`$cmd -D test --update --replace --run-time 1s`;
ok($dbh->selectrow_array('select id from test.heartbeat'), 'Record is there');

# Check the delay and ensure it is only a single line with nothing but the
# delay (no leading whitespace or anything).
$output = `$cmd -D test --check`;
chomp $output;
like($output, qr/^\d+$/, 'Output is just a number');

# Start one daemonized instance to update it
system("$cmd --daemonize -D test --update --run-time 3s --pid $pid_file 1>/dev/null 2>/dev/null");
$output = `$ps_grep_cmd`;
like($output, qr/$cmd/, 'It is running');

ok(-f $pid_file, 'PID file created');
my ($pid) = $output =~ /^\s*(\d+)\s+/;
$output = `cat $pid_file`;
is($output, $pid, 'PID file has correct PID');

$output = `$cmd -D test --monitor --run-time 1s`;
chomp ($output);
is (
   $output,
   '   0s [  0.00s,  0.00s,  0.00s ]',
   'It is being updated',
);
sleep(3);
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
$dbh->do('drop table if exists test.heartbeat'); # This will kill it

# #############################################################################
# Issue 353: Add --create-table to mk-heartbeat
# #############################################################################

# These creates the new table format, whereas the preceding tests used the
# old format, so tests from here on may need --master-server-id.

$dbh->do('drop table if exists test.heartbeat');
diag(`$cmd --update --run-time 1s --database test --table heartbeat --create-table`);
$dbh->do('use test');
$output = $dbh->selectcol_arrayref('SHOW TABLES LIKE "heartbeat"');
is(
   $output->[0],
   'heartbeat', 
   '--create-table creates heartbeat table'
); 

# #############################################################################
# Issue 352: Add port to mk-heartbeat --check output
# #############################################################################
sleep 1;
$output = `$cmd --host 127.1 --user msandbox --password msandbox --port 12345 -D test --check --recurse 1 --master-server-id 12345`;
like(
   $output,
   qr/:12346\s+\d/,
   '--check output has :port'
);

# #############################################################################
# Done.
# #############################################################################
`rm $pid_file $sent_file 2>/dev/null`;
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
