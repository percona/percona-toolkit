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
use File::Basename;
use File::Temp qw(tempdir);

$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1; 
$ENV{PRETTY_RESULTS} = 1; 

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-upgrade";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('host1');

my $host1_dsn   = $sb->dsn_for('host1');
my $tmpdir      = tempdir("/tmp/pt-upgrade.$PID.XXXXXX", CLEANUP => 1);
my $samples     = "$trunk/t/pt-upgrade/samples";
my $lib_samples = "$trunk/t/lib/samples";
my ($output, $exit_code);

# Testing if we are using DBD::mysql compiled with MariaDB library, which does not support enforcing SSL encryption
($output, $exit_code) = full_output(
   sub {
      pt_upgrade::main("${host1_dsn},u=msandbox,p=msandbox,s=1", '--save-results', $tmpdir,
         qw(--type rawlog),
         "$samples/select_into.log",
   )},
   stderr => 1,
);

if ( $exit_code != 0 || $output =~ /SSL connection error: Enforcing SSL encryption is not supported/ ) {
   plan skip_all => "Test does not work with DBD::mysql compiled with MariaDB library that does not support enforcing SSL encryption";
}
elsif ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox host1'; 
}
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}

# #############################################################################
# genlog
# #############################################################################

`rm -f /tmp/test_select_into_*.log`;

$sb->do_as_root(
   'host1',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT ALL ON *.* TO sha256_user@'%'/,
);

($output, $exit_code) = full_output(
   sub {
      pt_upgrade::main("${host1_dsn},u=sha256_user,p=sha256_user%password,s=0", '--save-results', $tmpdir,
         qw(--type rawlog),
         "$samples/select_into.log",
   )},
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
      pt_upgrade::main("${host1_dsn},u=sha256_user,p=sha256_user%password,s=1", '--save-results', $tmpdir,
         qw(--type rawlog),
         "$samples/select_into.log",
   )},
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

is(
   $exit_code,
   0,
   "Does not fail on SELECT...INTO statements"
);

($output, $exit_code) = full_output(
   sub {
      pt_upgrade::main("${host1_dsn}",
         qw(--user sha256_user --password sha256_user%password --mysql_ssl 1),
         '--save-results', $tmpdir,
         qw(--type rawlog),
         "$samples/select_into.log",
   )},
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password with option --mysql_ssl"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with option --mysql_ssl'
) or diag($output);

is(
   $exit_code,
   0,
   "Does not fail on SELECT...INTO statements with option --mysql_ssl"
);

($output, $exit_code) = full_output(
   sub {
      pt_upgrade::main("F=t/pt-archiver/samples/pt-191.cnf,${host1_dsn},u=sha256_user,p=sha256_user%password,s=1", '--save-results', $tmpdir,
         qw(--type rawlog),
         "$samples/select_into.log")
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

($output, $exit_code) = full_output(
   sub {
      pt_upgrade::main("F=t/pt-archiver/samples/pt-191-error.cnf,${host1_dsn},u=sha256_user,p=sha256_user%password,s=1", '--save-results', $tmpdir,
         qw(--type rawlog),
         "$samples/select_into.log")
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

($output, $exit_code) = full_output(
   sub {
      pt_upgrade::main("${host1_dsn},u=sha256_user,p=sha256_user%password,s=1,o=1", '--save-results', $tmpdir,
         qw(--type rawlog),
         "$samples/select_into.log",
   )},
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password with option --mysql_ssl_optional (short version -o)"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with option --mysql_ssl_optional (short version -o)'
) or diag($output);

is(
   $exit_code,
   0,
   "Does not fail on SELECT...INTO statements with option --mysql_ssl_optional (short version -o)"
);

($output, $exit_code) = full_output(
   sub {
      pt_upgrade::main("${host1_dsn}",
         qw(--user sha256_user --password sha256_user%password --mysql_ssl 1 --mysql_ssl_optional 1),
         '--save-results', $tmpdir,
         qw(--type rawlog),
         "$samples/select_into.log",
   )},
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password with option --mysql_ssl and --mysql_ssl_optional"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with option --mysql_ssl and --mysql_ssl_optional'
) or diag($output);

is(
   $exit_code,
   0,
   "Does not fail on SELECT...INTO statements with option --mysql_ssl and --mysql_ssl_optional"
);

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root('host1', q/DROP USER 'sha256_user'@'%'/);

$sb->wipe_clean($dbh1);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
