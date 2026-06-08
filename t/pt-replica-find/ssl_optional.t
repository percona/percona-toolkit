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
require "$trunk/bin/pt-replica-find";

if ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica2_dbh = $sb->get_dbh_for('replica2');
my $output;

# Testing if we are using DBD::mysql compiled with MariaDB library, which does not support enforcing SSL encryption
$output = `$trunk/bin/pt-replica-find h=127.1,P=12345,u=msandbox,p=msandbox,s=1 --report-format hostname 2>&1`;

if ( $? == 0 || $output !~ /SSL connection error: Enforcing SSL encryption is not supported/ ) {
   plan skip_all => "Test requires DBD::mysql compiled with MariaDB library that does not support enforcing SSL encryption";
}
elsif ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}
elsif ( !$replica2_dbh ) {
   plan skip_all => 'Cannot connect to second sandbox replica';
}

# This test is sensitive to ghost/old replicas created/destroyed by other
# tests.  So we stop the replicas, restart the source, and start everything
# again.  Hopefully this will return the env to its original state.
$replica2_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("STOP ${replica_name}");
diag(`/tmp/12345/stop >/dev/null`);
diag(`/tmp/12345/start >/dev/null`);
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("START ${replica_name}");

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT REPLICATION SLAVE, PROCESS ON *.* TO sha256_user@'%'/,
);

# Start an instance
$output = `$trunk/bin/pt-replica-find h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=0 --report-format hostname 2>&1`;

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

$output = `$trunk/bin/pt-replica-find h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1 --report-format hostname 2>&1`;

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

my $expected = <<EOF;
127.1:12345
+- 127.0.0.1:12346
   +- 127.0.0.1:12347
EOF

is($output, $expected, 'Source with replica and replica of replica');

$output = `$trunk/bin/pt-replica-find --host=127.1 --port=12345 --user=sha256_user --password=sha256_user%password --mysql_ssl=1 --mysql_ssl_optional=1 --report-format hostname 2>&1`;

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

$expected = <<EOF;
127.1:12345
+- 127.0.0.1:12346
   +- 127.0.0.1:12347
EOF

is(
   $output,
   $expected,
   'Source with replica and replica of replica with option --mysql_ssl'
);

$output = `$trunk/bin/pt-replica-find F=t/pt-archiver/samples/pt-191.cnf,h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1 --report-format hostname  --recurse 0 2>&1`;

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

$output = `$trunk/bin/pt-replica-find F=t/pt-archiver/samples/pt-191-error.cnf,h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1 --report-format hostname  --recurse 0 2>&1`;

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
$sb->do_as_root('source', q/DROP USER 'sha256_user'@'%'/);

ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
