#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use PerconaTest;
use Sandbox;
use DSNParser;
require VersionParser;
use Test::More;
use File::Temp qw( tempdir );

local $ENV{PTDEBUG} = "";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox';
}
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}
else {
   plan tests => 10;
}

my ($tool) = 'pt-mysql-summary';

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT ALL ON sakila.* TO sha256_user@'%'/,
);

my $output = `$trunk/bin/$tool --host=127.1 --port=12345 --user=sha256_user --password=sha256_user%password 2>&1 -- --defaults-file=/tmp/12345/my.sandbox.cnf --ssl-mode=disabled`;

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

$output = `$trunk/bin/$tool --host=127.1 --port=12345 --user=sha256_user --password=sha256_user%password 2>&1 -- --defaults-file=/tmp/12345/my.sandbox.cnf --ssl-mode=required`;

is(
   $?,
   0,
   "No error for user, identified with caching_sha2_password"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error'
) or diag($output);

like(
   $output,
   qr/SSL | Yes/,
   "Authentication with caching_sha2_password works"
);

$output = `$trunk/bin/$tool --host=127.1 --port=12345 --user=sha256_user --password=sha256_user%password 2>&1 -- --defaults-file=t/pt-archiver/samples/pt-191.cnf --ssl-mode=required`;

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

$output = `$trunk/bin/$tool --host=127.1 --port=12345 --user=sha256_user --password=sha256_user%password 2>&1 -- --defaults-file=t/pt-archiver/samples/pt-191-error.cnf --ssl-mode=required`;

isnt(
   $?,
   0,
   "Error for invalid SSL options in the configuration file"
) or diag($output);

like(
   $output,
   qr/SSL error: Unable to get private key from/,
   'SSL connection error with incorrect SSL options in the configuration file'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root('source', q/DROP USER 'sha256_user'@'%'/);

$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
