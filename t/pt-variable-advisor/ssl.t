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
require "$trunk/bin/pt-variable-advisor";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');
my $dsn = $sb->dsn_for('source');

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox source";
}
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1168106
# pt-variable-advisor has the wrong default value for
# innodb_max_dirty_pages_pct in 5.6.10
# #############################################################################

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT ALL ON sakila.* TO sha256_user@'%'/,
);

my ($output, $exit_code);

($output, $exit_code) = full_output(
   sub { pt_variable_advisor::main("${dsn},u=sha256_user,p=sha256_user%password,s=0") },
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
   sub { pt_variable_advisor::main("${dsn},u=sha256_user,p=sha256_user%password,s=1") },
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

unlike(
   $output,
   qr/innodb_max_dirty_pages_pct/,
   "No innodb_max_dirty_pages_pct warning (bug 1168106)"
);

($output, $exit_code) = full_output(
   sub { pt_variable_advisor::main("${dsn}",
         qw(--user sha256_user --password sha256_user%password --mysql_ssl 1)) },
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

unlike(
   $output,
   qr/innodb_max_dirty_pages_pct/,
   "No innodb_max_dirty_pages_pct warning (bug 1168106) with option --mysql_ssl"
);

($output, $exit_code) = full_output(
   sub { pt_variable_advisor::main("F=t/pt-archiver/samples/pt-191.cnf,${dsn},u=sha256_user,p=sha256_user%password,s=1") },
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
   sub { pt_variable_advisor::main("F=t/pt-archiver/samples/pt-191-error.cnf,${dsn},u=sha256_user,p=sha256_user%password,s=1") },
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

ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
