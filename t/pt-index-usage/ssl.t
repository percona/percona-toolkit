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
require "$trunk/bin/pt-index-usage";
require VersionParser;

use Sandbox;
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

my $cnf     = '/tmp/12345/my.sandbox.cnf';
my @args    = ('-F', $cnf);
my $samples = "t/pt-index-usage/samples/";
my ($output, $exit_code);

# Testing if we are using DBD::mysql compiled with MariaDB library, which does not support enforcing SSL encryption
($output, $exit_code) = full_output(
   sub { pt_index_usage::main(
         @args,
         qw(--host=127.1 --port=12345 --user=msandbox --password=msandbox --mysql_ssl=1),
         "$trunk/$samples/slow001.txt")
   },
   stderr => 1,
);

if ( $exit_code != 0 || $output =~ /SSL connection error: Enforcing SSL encryption is not supported/ ) {
   plan skip_all => "Test does not work with DBD::mysql compiled with MariaDB library that does not support enforcing SSL encryption";
}
elsif ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}
elsif ( !@{ $dbh->selectall_arrayref("show databases like 'sakila'") } ) {
   plan skip_all => "Sakila database is not loaded";
}

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT ALL ON sakila.* TO sha256_user@'%'/,
   q/GRANT ALL ON test.* TO sha256_user@'%'/,
);

# This query doesn't use indexes so there's an unused PK and
# an unused secondary index.  Only the secondary index should
# be printed since dropping PKs is not suggested by default.

($output, $exit_code) = full_output(
   sub {
      pt_index_usage::main(
         @args,
         qw(--host=127.1 --port=12345 --user=sha256_user --password=sha256_user%password --mysql_ssl=0),
         "$trunk/$samples/slow001.txt")
   },
   stderr => 1,
);

isnt(
   $exit_code,
   0,
   "Error raised when SSL connection is not used"
) or diag($output);

like(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'Secure connection error raised when no SSL connection used'
) or diag($output);

($output, $exit_code) = full_output(
   sub {
      pt_index_usage::main(
         @args,
         qw(--host=127.1 --port=12345 --user=sha256_user --password=sha256_user%password --mysql_ssl=1),
         "$trunk/$samples/slow001.txt")
   },
   stderr => 1,
);

is(
   $exit_code,
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
   qr/ALTER TABLE `sakila`.`film_text` DROP KEY `idx_title_description`; -- type:non-unique/,
   'A simple query that does not use any indexes',
) or diag($output);

($output, $exit_code) = full_output(
   sub {
      pt_index_usage::main(
         @args,
         qw(--host=127.1 --port=12345 --user=sha256_user --password=sha256_user%password --mysql_ssl=1),
         qw(--create-save-results-database),
         '--save-results-database=h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,D=test',
         "$trunk/$samples/slow001.txt")
   },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password via DSN"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with DSN'
) or diag($output);

$output = `/tmp/12345/use -N -e "SHOW TABLES FROM test"`;

my $expected = <<EOF;
index_alternatives
index_usage
indexes
queries
tables
EOF

is(
   $output,
   $expected, 
   'Results are saved'
) or diag($output);

@args = ('-F', "$trunk/t/pt-archiver/samples/pt-191.cnf");
($output, $exit_code) = full_output(
   sub {
      pt_index_usage::main(
         @args,
         qw(--host=127.1 --port=12345 --user=sha256_user --password=sha256_user%password --mysql_ssl=1),
         "$trunk/$samples/slow001.txt")
   },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for SSL options in the configuration file"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with correct SSL options in the configuration file'
) or diag($output);

@args = ('-F', "$trunk/t/pt-archiver/samples/pt-191-error.cnf");
($output, $exit_code) = full_output(
   sub {
      pt_index_usage::main(
         @args,
         qw(--host=127.1 --port=12345 --user=sha256_user --password=sha256_user%password --mysql_ssl=1),
         "$trunk/$samples/slow001.txt")
   },
   stderr => 1,
);

isnt(
   $exit_code,
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

@args    = ('-F', $cnf);

($output, $exit_code) = full_output(
   sub {
      pt_index_usage::main(
         @args,
         qw(--host=127.1 --port=12345 --user=sha256_user --password=sha256_user%password --mysql_ssl=1 --mysql_ssl_optional=1),
         "$trunk/$samples/slow001.txt")
   },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password with option --mysql_ssl_optional 1 --mysql_ssl"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with option --mysql_ssl_optional 1 --mysql_ssl'
) or diag($output);

like(
   $output,
   qr/ALTER TABLE `sakila`.`film_text` DROP KEY `idx_title_description`; -- type:non-unique/,
   'A simple query that does not use any indexes with option --mysql_ssl_optional 1 --mysql_ssl',
) or diag($output);

($output, $exit_code) = full_output(
   sub {
      pt_index_usage::main(
         @args,
         qw(--host=127.1 --port=12345 --user=sha256_user --password=sha256_user%password --mysql_ssl=1),
         qw(--create-save-results-database),
         '--save-results-database=h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1,D=test',
         "$trunk/$samples/slow001.txt")
   },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password via DSN with option --mysql_ssl_optional 1"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with DSN with option --mysql_ssl_optional 1'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root('source', q/DROP USER 'sha256_user'@'%'/);

$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
