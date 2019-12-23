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
my $slave1_dbh = $sb->get_dbh_for('slave1');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

my $num_rows = 1000;
my $table = 't1';

$dbh->do("DROP DATABASE IF EXISTS test");
$dbh->do("CREATE DATABASE IF NOT EXISTS test");
$dbh->do("CREATE TABLE `test`.`$table` (id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(5)) Engine=InnoDB");

diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test $table $num_rows`);
$slave1_dbh->do("DELETE FROM `test`.`$table` WHERE 1=1");

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

like(
   $output,
   qr/100\s+1000\s+10\s+102\s+0\s+\d+\.\d+\s+test.t1/,
   "Truncating tables while checksum is running"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
