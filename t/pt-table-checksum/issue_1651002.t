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
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
else {
   plan tests => 7;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox,D=test,s=1';
my @args       = ($source_dsn, qw(--replicate test.checksums -d test --replica-user replica_user --replica-password replica_password --ignore-databases mysql)); 
my $output;

# Create a new user that is going to be replicated on replicas.
# After that, stop replication, delete the user from the source just to ensure that
# on the source we are using the sandbox user, and start relication again to run
# the tests
if ($sandbox_version eq '8.0') {
    $sb->do_as_root("replica1", q/CREATE USER 'replica_user'@'localhost' IDENTIFIED WITH mysql_native_password BY 'replica_password'/);
} else {
    $sb->do_as_root("replica1", q/CREATE USER 'replica_user'@'localhost' IDENTIFIED BY 'replica_password'/);
}
$sb->do_as_root("replica1", q/GRANT REPLICATION CLIENT ON *.* TO 'replica_user'@'localhost'/);
$sb->do_as_root("replica1", q/GRANT ALL ON *.* TO 'replica_user'@'localhost'/);                
$sb->do_as_root("replica1", q/FLUSH PRIVILEGES/);                

$sb->wait_for_replicas();

$sb->load_file('source', 't/pt-table-checksum/samples/issue_1651002.sql');
# Ensure we cannot connect to replicas using standard credentials
# Since replica2 is a replica of replica1, removing the user from the replica1 will remove
# the user also from replica2
$sb->do_as_root("replica1", q/RENAME USER 'msandbox'@'%' TO 'msandbox_old'@'%'/);
$sb->do_as_root("replica1", q/FLUSH PRIVILEGES/);
$sb->do_as_root("replica1", q/FLUSH TABLES/);

$output = output(
   sub { pt_table_checksum::main(@args) },
   stderr => 1,
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   6,
   "Large BLOB/TEXT/BINARY Checksum"
) or diag($output);

unlike(
   $output,
   qr/Option --slave-user is deprecated and will be removed in future versions./,
   'Deprecation warning not printed when option --replica-user provided'
) or diag($output);

unlike(
   $output,
   qr/Option --slave-password is deprecated and will be removed in future versions./,
   'Deprecation warning not printed when option --replica-password provided'
) or diag($output);

#Legacy variant

@args = ($source_dsn, qw(--replicate test.checksums -d test --slave-user replica_user --slave-password replica_password --ignore-databases mysql)); 

$output = output(
   sub { pt_table_checksum::main(@args) },
   stderr => 1,
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   6,
   "Large BLOB/TEXT/BINARY Checksum"
) or diag($output);

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

# #############################################################################
# Done.
# #############################################################################
diag("Stopping the sandbox to leave a clean sandbox for the next test file");

$sb->do_as_root("replica1", q/DROP USER 'replica_user'@'localhost'/);
$sb->do_as_root("replica1", q/FLUSH PRIVILEGES/);

# Restore privilegs for the other test files
$sb->do_as_root("replica1", q/RENAME USER 'msandbox_old'@'%' TO 'msandbox'@'%'/);
$sb->do_as_root("source", q/FLUSH PRIVILEGES/);                
$sb->do_as_root("source", q/FLUSH TABLES/);

$sb->wipe_clean($dbh);

ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

exit;
