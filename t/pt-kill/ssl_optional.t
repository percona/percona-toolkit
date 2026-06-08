#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
   $ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-kill";
require VersionParser;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');

my ($output, $exit_code);
my $cnf = '/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-kill";

# Testing if we are using DBD::mysql compiled with MariaDB library, which does not support enforcing SSL encryption
$output = `$cmd F=$cnf,h=127.1,P=12345,u=msandbox,p=msandbox,s=1 --busy-time 1s --print --run-time 1 2>&1`;

if ( $? == 0 || $output !~ /SSL connection error: Enforcing SSL encryption is not supported/ ) {
   plan skip_all => "Test requires DBD::mysql compiled with MariaDB library that does not support enforcing SSL encryption";
}
elsif ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}
else {
   plan tests => 13;
}

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT PROCESS ON *.* TO sha256_user@'%'/,
);

$output = `$cmd F=$cnf,h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=0 --busy-time 1s --print --run-time 10 2>&1`;

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

# Shell out to a sleep(10) query and try to capture the query.
# Backticks don't work here.
system("/tmp/12345/use -e 'select sleep(5)' >/dev/null &");

$output = `$cmd F=$cnf,h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1 --busy-time 1s --print --run-time 10 2>&1`;

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

# $output ought to be something like
# 2009-05-27T22:19:40 KILL 5 (Query 1 sec) select sleep(10)
# 2009-05-27T22:19:41 KILL 5 (Query 2 sec) select sleep(10)
# 2009-05-27T22:19:42 KILL 5 (Query 3 sec) select sleep(10)
# 2009-05-27T22:19:43 KILL 5 (Query 4 sec) select sleep(10)
# 2009-05-27T22:19:44 KILL 5 (Query 5 sec) select sleep(10)
# 2009-05-27T22:19:45 KILL 5 (Query 6 sec) select sleep(10)
# 2009-05-27T22:19:46 KILL 5 (Query 7 sec) select sleep(10)
# 2009-05-27T22:19:47 KILL 5 (Query 8 sec) select sleep(10)
# 2009-05-27T22:19:48 KILL 5 (Query 9 sec) select sleep(10)
my @times = $output =~ m/\(Query (\d+) sec\)/g;
ok(
   @times > 2 && @times < 7,
   "There were 2 to 5 captures"
) or diag($output);

# Shell out to a sleep(10) query and try to capture the query.
# Backticks don't work here.
system("/tmp/12345/use -e 'select sleep(5)' >/dev/null &");

$output = `$cmd --host 127.1 --port 12345 --user sha256_user --password=sha256_user%password --mysql_ssl 1 --mysql_ssl_optional=1 --busy-time 1s --print --run-time 10 2>&1`;

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

# $output ought to be something like
# 2009-05-27T22:19:40 KILL 5 (Query 1 sec) select sleep(10)
# 2009-05-27T22:19:41 KILL 5 (Query 2 sec) select sleep(10)
# 2009-05-27T22:19:42 KILL 5 (Query 3 sec) select sleep(10)
# 2009-05-27T22:19:43 KILL 5 (Query 4 sec) select sleep(10)
# 2009-05-27T22:19:44 KILL 5 (Query 5 sec) select sleep(10)
# 2009-05-27T22:19:45 KILL 5 (Query 6 sec) select sleep(10)
# 2009-05-27T22:19:46 KILL 5 (Query 7 sec) select sleep(10)
# 2009-05-27T22:19:47 KILL 5 (Query 8 sec) select sleep(10)
# 2009-05-27T22:19:48 KILL 5 (Query 9 sec) select sleep(10)
@times = $output =~ m/\(Query (\d+) sec\)/g;
ok(
   @times > 2 && @times < 7,
   "There were 2 to 5 captures with option --mysql_ssl"
) or diag($output);

$output = `$cmd F=t/pt-archiver/samples/pt-191.cnf,h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1 --busy-time 1s --print --run-time 10 2>&1`;

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

$output = `$cmd F=t/pt-archiver/samples/pt-191-error.cnf,h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1 --busy-time 1s --print --run-time 10 2>&1`;

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

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
