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
use SqlModes;
use threads;
use Time::HiRes qw( usleep );
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

my $num_rows = 1_000_000;
my $table = 't1';

$dbh->do("DROP DATABASE IF EXISTS test");
$dbh->do("CREATE DATABASE IF NOT EXISTS test");
$dbh->do("CREATE TABLE `test`.`$table` (id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(5)) Engine=InnoDB");

diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test $table $num_rows`);

sub start_thread {
   my ($dsn_opts, $initial_sleep_time) = @_;
   my $dp = new DSNParser(opts=>$dsn_opts);
   my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
   my $master_dbh = $sb->get_dbh_for('master');
   my $slave_dbh = $sb->get_dbh_for('slave1');
   diag("Sleeping");
   sleep($initial_sleep_time);
   diag("Woke up");
   $slave_dbh->do("STOP SLAVE IO_THREAD FOR CHANNEL ''");
   $slave_dbh->do("STOP SLAVE");
   $master_dbh->do("TRUNCATE TABLE test.$table");
   # PTDEBUG && diag("Exit thread")
   sleep(2);
   $slave_dbh->do("START SLAVE");
   diag("Exit thread")
}
# This is not a realiable sleep value. It works for a i7, hybrid HDD
my $initial_sleep_time = 17;
my $thr = threads->create('start_thread', $dsn_opts, $initial_sleep_time);
threads->yield();

diag("Starting checksum");
# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--no-check-binlog-format --chunk-size 10)); 
my $output;

$output = output(
   sub { pt_table_checksum::main(@args) },
   stderr => 1,
);

diag($output);
unlike(
   $output,
   qr/Can't use an undefined value as an ARRAY/,
   "Truncating tables while checksum is running"
);

$thr->join();

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
