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
require "$trunk/bin/pt-replica-restart";

if ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}

my $output;

# Testing if we are using DBD::mysql compiled with MariaDB library, which does not support enforcing SSL encryption
$output = `$trunk/bin/pt-replica-restart --max-sleep 0.25 h=127.1,P=12346,u=msandbox,p=msandbox,s=1 --error-text "doesn't exist" --run-time 1s 2>&1`;

if ( $? == 0 || $output !~ /SSL connection error: Enforcing SSL encryption is not supported/ ) {
   plan skip_all => "Test requires DBD::mysql compiled with MariaDB library that does not support enforcing SSL encryption";
}

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
$source_dbh->do('DROP TABLE IF EXISTS test.t');
$source_dbh->do('CREATE TABLE test.t (a INT)');
sleep 1;
$replica_dbh->do('DROP TABLE test.t');
$source_dbh->do('INSERT INTO test.t SELECT 1');
$output = `/tmp/12346/use -e "show ${replica_name} status"`;
like(
   $output,
   qr/Table 'test.t' doesn't exist'/,
   'It is busted'
);

$sb->do_as_root(
   'replica1',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT REPLICATION SLAVE, PROCESS ON *.* TO sha256_user@'%'/,
);

# Start an instance
$output = `$trunk/bin/pt-replica-restart --max-sleep 0.25 h=127.1,P=12346,u=sha256_user,p=sha256_user%password,s=0 --error-text "doesn't exist" --run-time 1s 2>&1`;

isnt(
   $?,
   0,
   "Error raised when SSL connection is not used"
) or diag($output);

like(
   $output,
   qr/Access denied/,
   'Secure connection error raised when no SSL connection used'
) or diag($output);

$output = `$trunk/bin/pt-replica-restart --max-sleep 0.25 h=127.1,P=12346,u=sha256_user,p=sha256_user%password,s=1,o=1 --error-text "doesn't exist" --run-time 1s 2>&1`;

is(
   $?,
   0,
   "No error for user, identified with caching_sha2_password"
) or diag($output);

unlike(
   $output,
   qr/Access denied/,
   'No secure connection error'
) or diag($output);

unlike(
   $output,
   qr/Error does not match/,
   '--error-text works (issue 459)'
);

$output = `$trunk/bin/pt-replica-restart --max-sleep 0.25 --host=127.1 --port=12346 --user=sha256_user --password=sha256_user%password --mysql_ssl=1 --mysql_ssl_optional=1 --error-text "doesn't exist" --run-time 1s 2>&1`;

is(
   $?,
   0,
   "No error for user, identified with caching_sha2_password with option --mysql_ssl"
) or diag($output);

unlike(
   $output,
   qr/Access denied/,
   'No secure connection error with option --mysql_ssl'
) or diag($output);

unlike(
   $output,
   qr/Error does not match/,
   '--error-text works (issue 459) with option --mysql_ssl'
);

$output = `$trunk/bin/pt-replica-restart --max-sleep 0.25 F=t/pt-archiver/samples/pt-191-replica1.cnf,h=127.1,P=12346,u=sha256_user,p=sha256_user%password,s=1,o=1 --error-text "doesn't exist" --run-time 1s 2>&1`;

is(
   $?,
   0,
   "No error for SSL options in the configuration file"
) or diag($output);

unlike(
   $output,
   qr/Access denied/,
   'No secure connection error with correct SSL options in the configuration file'
) or diag($output);

$output = `$trunk/bin/pt-replica-restart --max-sleep 0.25 F=t/pt-archiver/samples/pt-191-error.cnf,h=127.1,P=12346,u=sha256_user,p=sha256_user%password,s=1,o=1 --error-text "doesn't exist" --run-time 1s 2>&1`;

isnt(
   $?,
   0,
   "Error for invalid SSL options in the configuration file"
) or diag($output);

like(
   $output,
   qr/SSL error: key values mismatch/,
   'SSL connection error with incorrect SSL options in the configuration file'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root('replica1', q/DROP USER 'sha256_user'@'%'/);

diag(`rm -f /tmp/pt-replica-re*`);
diag(`$trunk/sandbox/test-env restart`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
