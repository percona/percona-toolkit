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

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox,D=test';
my @args       = ($master_dsn, qw(--replicate test.checksums -d test --slave-user slave_user --slave-password slave_password --ignore-databases mysql)); 
my $output;

# Create a new user that is going to be replicated on slaves.
# After that, stop replication, delete the user from the master just to ensure that
# on the master we are using the sandbox user, and start relication again to run
# the tests
$sb->do_as_root("slave1", q/GRANT REPLICATION CLIENT ON *.* TO 'slave_user'@'localhost' IDENTIFIED BY 'slave_password'/);
$sb->do_as_root("slave1", q/GRANT ALL ON *.* TO 'slave_user'@'localhost'/);                
$sb->do_as_root("slave1", q/FLUSH PRIVILEGES/);                

$sb->do_as_root("slave2", q/GRANT REPLICATION CLIENT ON *.* TO 'slave_user'@'localhost' IDENTIFIED BY 'slave_password'/);
$sb->do_as_root("slave2", q/GRANT ALL ON *.* TO 'slave_user'@'localhost'/);                
$sb->do_as_root("slave2", q/FLUSH PRIVILEGES/);                

$sb->wait_for_slaves();

# Run these commands inside issue_1651002.sql to delete the sandbox user ONLY from master
# These command must be in the .sql file because all of them need to run in the same session
# set sql_log_bin=0;
# DROP USER 'slave_user';
# set sql_log_bin=1;
$sb->load_file('master', 't/pt-table-checksum/samples/issue_1651002.sql');
# Ensure we cannot connect to slaves using standard credentials
# Since slave2 is a slave of slave1, removing the user from the slave1 will remove
# the user also from slave2
$sb->do_as_root("slave1", q/DROP USER 'msandbox'@'%'/);
$sb->do_as_root("slave1", q/FLUSH PRIVILEGES/);


$output = output(
   sub { pt_table_checksum::main(@args) },
   stderr => 1,
);
is(
   PerconaTest::count_checksum_results($output, 'rows'),
   6,
   "Large BLOB/TEXT/BINARY Checksum"
);

# Restore privilegs for the other test files
$sb->do_as_root("master", q/GRANT ALL PRIVILEGES ON *.* TO 'msandbox'@'%' IDENTIFIED BY 'msandbox'/);                
$sb->do_as_root("master", q/FLUSH PRIVILEGES/);                

$sb->do_as_root("slave1", q/GRANT ALL PRIVILEGES ON *.* TO 'msandbox'@'%' IDENTIFIED BY 'msandbox'/);                
$sb->do_as_root("slave1", q/FLUSH PRIVILEGES/);                
# #############################################################################
# Done.
# #############################################################################
diag("Stopping the sandbox to leave a clean sandbox for the next test file");
$sb->do_as_root("slave1", q/DROP USER 'slave_user'@'localhost'/);
$sb->do_as_root("slave1", q/FLUSH PRIVILEGES/);

$sb->wipe_clean($dbh);

ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

exit;
