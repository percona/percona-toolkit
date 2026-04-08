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
require "$trunk/bin/pt-find";

require VersionParser;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-find";

# Testing if we are using DBD::mysql compiled with MariaDB library, which does not support enforcing SSL encryption
$output = `$cmd -F $cnf --host=127.0.0.1 --port=12345 mysql --tblregex column --user=msandbox --password=msandbox --mysql_ssl=1 2>&1`; 

if ( $? != 0 || $output =~ /SSL connection error: Enforcing SSL encryption is not supported/ ) {
   plan skip_all => "Test does not work with DBD::mysql compiled with MariaDB library that does not support enforcing SSL encryption";
}

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT ALL ON *.* TO sha256_user@'%'/,
);

$output = `$cmd -F $cnf --host=127.0.0.1 --port=12345 mysql --tblregex column --user=sha256_user --password=sha256_user%password --mysql_ssl=0 2>&1`; 

isnt(
   $?,
   0,
   "Error raised when SSL connection is not used"
) or diag($output);

like(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'Secure connection error raised when no SSL connection used'
) or diag($output);

$output = `$cmd -F $cnf --host=127.0.0.1 --port=12345 mysql --tblregex column --user=sha256_user --password=sha256_user%password --mysql_ssl=1 2>&1`; 

is(
   $?,
   0,
   "Error not raised when SSL connection is used"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error raised when SSL connection used'
) or diag($output);

like($output, qr/`mysql`.`columns_priv`/, 'Found mysql.columns_priv');

$dbh->do('CREATE DATABASE IF NOT EXISTS test');
$dbh->do('CREATE TABLE test.pt_find_ssl(cnt INT)');

$output = `$cmd -F $cnf --host=127.0.0.1 --port=12345 mysql --tblregex column --user=sha256_user --password=sha256_user%password --mysql_ssl=1 --exec-dsn=h=127.1,P=12346,u=sha256_user,p=sha256_user%password,s=1 --exec-plus "INSERT INTO test.pt_find_ssl() SELECT COUNT(*) FROM %s" 2>&1`; 

is(
   $?,
   0,
   "Error not raised when SSL connection is used with DSN"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error raised when SSL connection used with DSN'
) or diag($output);

$output = `/tmp/12346/use -N -e "SELECT COUNT(*) FROM test.pt_find_ssl"`;
chomp($output);

is(
   $output,
   1, 
   'DSN option s works with pt-find'
) or diag($output);

$output = `$cmd -F t/pt-archiver/samples/pt-191.cnf --host=127.0.0.1 --port=12345 mysql --tblregex column --user=sha256_user --password=sha256_user%password --mysql_ssl=1 2>&1`; 

is(
   $?,
   0,
   "No error for SSL options in the configuration file"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with correct SSL options in the configuration file'
) or diag($output);

$output = `$cmd -F t/pt-archiver/samples/pt-191-error.cnf --host=127.0.0.1 --port=12345 mysql --tblregex column --user=sha256_user --password=sha256_user%password --mysql_ssl=1 2>&1`; 

isnt(
   $?,
   0,
   "Error for invalid SSL options in the configuration file"
) or diag($output);

like(
   $output,
   qr/SSL connection error: Unable to get private key at/,
   'SSL connection error with incorrect SSL options in the configuration file'
) or diag($output);

# #############################################################################
# Test mysql_ssl_optional option
# #############################################################################

$output = `$cmd -F $cnf --host=127.0.0.1 --port=12345 mysql --tblregex column --user=sha256_user --password=sha256_user%password --mysql_ssl=1 --mysql_ssl_optional=1 2>&1`; 

is(
   $?,
   0,
   "Error not raised when SSL connection is used with mysql_ssl_optional"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error raised when SSL connection used with mysql_ssl_optional'
) or diag($output);

like($output, qr/`mysql`.`columns_priv`/, 'Found mysql.columns_priv with mysql_ssl_optional');

$output = `$cmd -F $cnf --host=127.0.0.1 --port=12345 mysql --tblregex column --user=sha256_user --password=sha256_user%password --mysql_ssl=1 --mysql_ssl_optional=1 --exec-dsn=h=127.1,P=12346,u=sha256_user,p=sha256_user%password,s=1,o=1 --exec-plus "INSERT INTO test.pt_find_ssl() SELECT COUNT(*) FROM %s" 2>&1`; 

is(
   $?,
   0,
   "Error not raised when SSL connection is used with DSN and mysql_ssl_optional"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error raised when SSL connection used with DSN and mysql_ssl_optional'
) or diag($output);

$output = `/tmp/12346/use -N -e "SELECT COUNT(*) FROM test.pt_find_ssl"`;
chomp($output);

is(
   $output,
   2, 
   'DSN option s works with pt-find and mysql_ssl_optional'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root('source', q/DROP USER 'sha256_user'@'%'/);

$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
