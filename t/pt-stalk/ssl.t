#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;
use English qw(-no_match_vars);
use Test::More;
use Time::HiRes qw(sleep);

use PerconaTest;
use DSNParser;
use Sandbox;
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

my $cnf      = "/tmp/12345/my.sandbox.cnf";
my $pid_file = "/tmp/pt-stalk.pid.$PID";
my $log_file = "/tmp/pt-stalk.log.$PID";
my $dest     = "/tmp/pt-stalk.collect.$PID";
my $int_file = "/tmp/pt-stalk-after-interval-sleep";
my $pid;
my ($output, $exit_code);

sub cleanup {
   diag(`rm $pid_file $log_file $int_file 2>/dev/null`);
   diag(`rm -rf $dest 2>/dev/null`);
}

cleanup();

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT SUPER ON *.* TO sha256_user@'%'/,
);

$exit_code = system("$trunk/bin/pt-stalk --host=127.1 --no-stalk --run-time 2 --dest $dest --prefix nostalk --pid $pid_file --iterations 1 --user=sha256_user --password=sha256_user%password -- --defaults-file=$cnf --ssl-mode=disabled >$log_file 2>&1");

PerconaTest::wait_until(sub { !-f $pid_file });

$output = `cat $log_file 2>/dev/null`;

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

cleanup();

$exit_code = system("$trunk/bin/pt-stalk --host=127.1 --no-stalk --run-time 2 --dest $dest --prefix nostalk --pid $pid_file --iterations 1 --user=sha256_user --password=sha256_user%password -- --defaults-file=$cnf --ssl-mode=required >$log_file 2>&1");

PerconaTest::wait_until(sub { !-f $pid_file });

$output = `cat $log_file 2>/dev/null`;

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

$output = `cat $dest/nostalk-trigger 2>/dev/null`;
like(
   $output,
   qr/Not stalking/,
   "Not stalking, collect triggered"
)
or diag(
   'dest',      `ls -l $dest/ 2>/dev/null`,
   'log_file',  `cat $log_file 2>/dev/null`,
   'collector', `cat $dest/*-output 2>/dev/null`,
);

chomp($output = `grep -c '^TS' $dest/nostalk-df 2>/dev/null`);
is(
   $output,
   2,
   "Not stalking, collect ran for --run-time"
)
or diag(
   'dest',      `ls -l $dest/ 2>/dev/null`,
   'log_file',  `cat $log_file 2>/dev/null`,
   'collector', `cat $dest/*-output 2>/dev/null`,
);

cleanup();

$exit_code = system("$trunk/bin/pt-stalk --host=127.1 --port=12345 --no-stalk --run-time 2 --dest $dest --prefix nostalk --pid $pid_file --iterations 1 --user=sha256_user --password=sha256_user%password -- --defaults-file=t/pt-archiver/samples/pt-191.cnf --ssl-mode=required >$log_file 2>&1");

PerconaTest::wait_until(sub { !-f $pid_file });

$output = `cat $log_file 2>/dev/null`;

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

cleanup();

$exit_code = system("$trunk/bin/pt-stalk --host=127.1 --port=12345 --no-stalk --run-time 2 --dest $dest --prefix nostalk --pid $pid_file --iterations 1 --user=sha256_user --password=sha256_user%password -- --defaults-file=t/pt-archiver/samples/pt-191-error.cnf --ssl-mode=required >$log_file 2>&1");

PerconaTest::wait_until(sub { !-f $pid_file });

$output = `cat $log_file 2>/dev/null`;

isnt(
   $exit_code,
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

cleanup();
diag(`rm -rf $dest 2>/dev/null`);
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
