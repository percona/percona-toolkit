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
require "$trunk/bin/pt-config-diff";

require VersionParser;
my $dp   = new DSNParser(opts=>$dsn_opts);
my $sb   = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh  = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}

my ($output, $exit_code);
my $cnf      = "/tmp/12345/my.sandbox.cnf";

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password'/,
   q/GRANT ALL ON sakila.* TO sha256_user@'%'/,
);

($output, $exit_code) = full_output(
   sub { pt_config_diff::main(
      'h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=0', 'h=127.1')
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
   sub { pt_config_diff::main(
      'h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1', 'h=127.1')
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

is(
   $output,
   "",
   "No output when no diff"
) or diag($output);

($output, $exit_code) = full_output(
   sub { pt_config_diff::main(
      qw(--host 127.1 --port 12345 --user sha256_user),
      qw(--password sha256_user%password --mysql_ssl 1),
      'h=127.1')
   },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password and option --mysql_ssl"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with option --mysql_ssl'
) or diag($output);

is(
   $output,
   "",
   "No output when no diff and option --mysql_ssl"
) or diag($output);

($output, $exit_code) = full_output(
   sub {
      pt_config_diff::main("F=t/pt-archiver/samples/pt-191.cnf,h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1", 'h=127.1')
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
      pt_config_diff::main("F=t/pt-archiver/samples/pt-191-error.cnf,h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1", 'h=127.1')
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
# Done.
# #############################################################################
$sb->do_as_root('source', q/DROP USER 'sha256_user'@'%'/);

$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
