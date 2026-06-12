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
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}


$sb->create_dbs($source_dbh, ['test']);

my $output;
my $cnf       = '/tmp/12345/my.sandbox.cnf';
my $cmd       = "$trunk/bin/pt-heartbeat -F $cnf ";
my $pid_file  = "/tmp/__pt-heartbeat-test.pid";
my $sent_file = "/tmp/pt-heartbeat-sentinel";
my $ps_grep_cmd = "ps x | grep pt-heartbeat | grep daemonize | grep -v grep";

diag(`rm $sent_file 2>/dev/null`);

# Loading heartbeat table
$sb->load_file('source', 't/pt-heartbeat/samples/heartbeat-table.sql');

# Start one daemonized instance to update it
system("$cmd --daemonize -D test --update --run-time 3s --pid $pid_file 1>/dev/null 2>/dev/null");
PerconaTest::wait_for_files($pid_file);
$output = `$ps_grep_cmd`;
like($output, qr/$cmd/, 'It is running');
ok(-f $pid_file, 'PID file created');
my ($pid) = $output =~ /^\s*(\d+)\s+/;
$output = `cat $pid_file` if -f $pid_file;
chomp($output);
is($output, $pid, 'PID file has correct PID');

$output = `$cmd -D test --monitor --run-time 1s --source-server-id 12345 2>&1`;
if ( $output ) {
   chomp ($output);
   $output =~ s/\d/0/g;
}
is(
   $output,
   '0.00s [  0.00s,  0.00s,  0.00s ]',
   'It is being updated',
);
unlike(
   $output,
   qr/The current checksum table uses deprecated column names./,
   'Deprecation warning not printed'
);

PerconaTest::wait_until(sub { !-f $pid_file });

$output = `$ps_grep_cmd`;
chomp $output;
unlike($output, qr/$cmd/, 'It is not running anymore');
ok(! -f $pid_file, 'PID file removed');

# Run again, create table with legacy structure, and check that the tool can work with it

# Loading legacy heartbeat table
$sb->load_file('source', 't/pt-heartbeat/samples/heartbeat-table-legacy.sql');

# Start one daemonized instance to update it
system("$cmd --daemonize -D test --update --run-time 3s --pid $pid_file 1>/dev/null 2>/dev/null");
PerconaTest::wait_for_files($pid_file);
$output = `$ps_grep_cmd`;
like($output, qr/$cmd/, 'It is running');
ok(-f $pid_file, 'PID file created');
($pid) = $output =~ /^\s*(\d+)\s+/;
$output = `cat $pid_file` if -f $pid_file;
chomp($output);
is($output, $pid, 'PID file has correct PID');

$output = `$cmd -D test --monitor --run-time 1s --source-server-id 12345 2>&1`;
if ( $output ) {
   chomp ($output);
   $output =~ s/\d/0/g;
}

like(
   $output,
   qr/0.00s \[  0.00s,  0.00s,  0.00s \]/,
   'It is being updated',
) or diag($output);

like(
   $output,
   qr/The current heartbeat table uses deprecated column names./,
   'Deprecation warning printed for legacy syntax'
);

PerconaTest::wait_until(sub { !-f $pid_file });

$output = `$ps_grep_cmd`;
chomp $output;
unlike($output, qr/$cmd/, 'It is not running anymore');
ok(! -f $pid_file, 'PID file removed');

# #############################################################################
# Done.
# #############################################################################
diag(`rm $pid_file $sent_file 2>/dev/null`);
$sb->wipe_clean($source_dbh);
# $sb->wipe_clean($replica1_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;
exit;
