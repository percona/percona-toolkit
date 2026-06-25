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
use Time::Local;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

# pt-tc does not buffer output with 5.7, at least it is not possible
# to catch buffering with the tee command we use for tests.
# Since main issue of buffering is getting data in K8 environments,
# and k8 environments mostly use 8.0+, no sense to test buffering with 5.7.
if ( $sandbox_version eq '5.7' ) {
   plan skip_all => 'Test requires 8.0 or newer';
}

if ( not `which ts 2>/dev/null` ) {
   plan skip_all => 'Test requires ts from the moreutils package';
}

my $output = `$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox,s=1 --set-vars innodb_lock_wait_timeout=3 --chunk-size=50 -d sakila --buffer-stdout 2>&1 | tee | ts '%m-%dT%H:%M:%S'`;

my @lines = split(/\n/, $output);
my @times = ( $lines[3] =~ m/\d\d-\d\dT\d\d:\d\d:\d\d/g );

is(
   scalar(@times),
   2,
   "Expected number of timestamp values"
) or diag($output);

my ($month, $day, $hour, $min, $sec) = split(/[T:-]+/, $times[0]);
my $time_ts = timelocal($sec, $min, $hour, $day, $month - 1);
($month, $day, $hour, $min, $sec) = split(/[T:-]+/, $times[1]);
my $time_tool = timelocal($sec, $min, $hour, $day, $month - 1);

cmp_ok(
   $time_ts - $time_tool, 'gt', 1,
   "Print delay is expected for the buffered output"
) or diag($output); 

$output = `$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox,s=1 --set-vars innodb_lock_wait_timeout=3 --chunk-size=50 -d sakila 2>&1 | tee | ts '%m-%dT%H:%M:%S'`;

@lines = split(/\n/, $output);
@times = ( $lines[3] =~ m/\d\d-\d\dT\d\d:\d\d:\d\d/g );

is(
   scalar(@times),
   2,
   "Expected number of timestamp values"
) or diag($output);

($month, $day, $hour, $min, $sec) = split(/[T:-]+/, $times[0]);
$time_ts = timelocal($sec, $min, $hour, $day, $month - 1);
($month, $day, $hour, $min, $sec) = split(/[T:-]+/, $times[1]);
$time_tool = timelocal($sec, $min, $hour, $day, $month - 1);

cmp_ok(
   $time_ts - $time_tool, 'gt', 1,
   "STDOUT is buffered by default"
) or diag($output); 

$output = `$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox,s=1 --set-vars innodb_lock_wait_timeout=3 --chunk-size=50 -d sakila --no-buffer-stdout 2>&1 | tee | ts '%m-%dT%H:%M:%S'`;

@lines = split(/\n/, $output);
@times = ( $lines[3] =~ m/\d\d-\d\dT\d\d:\d\d:\d\d/g );

is(
   scalar(@times),
   2,
   "Expected number of timestamp values"
) or diag($output);

($month, $day, $hour, $min, $sec) = split(/[T:-]+/, $times[0]);
$time_ts = timelocal($sec, $min, $hour, $day, $month - 1);
($month, $day, $hour, $min, $sec) = split(/[T:-]+/, $times[1]);
$time_tool = timelocal($sec, $min, $hour, $day, $month - 1);

cmp_ok(
   $time_ts - $time_tool, 'le', 1,
   "Print delay is not expected when buffering is disabled"
) or diag($output); 

$output = `$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox,s=1 --set-vars innodb_lock_wait_timeout=3 --chunk-size=50 -d sakila --nobuffer-stdout 2>&1 | tee | ts '%m-%dT%H:%M:%S'`;

@lines = split(/\n/, $output);
@times = ( $lines[3] =~ m/\d\d-\d\dT\d\d:\d\d:\d\d/g );

is(
   scalar(@times),
   2,
   "Expected number of timestamp values"
) or diag($output);

($month, $day, $hour, $min, $sec) = split(/[T:-]+/, $times[0]);
$time_ts = timelocal($sec, $min, $hour, $day, $month - 1);
($month, $day, $hour, $min, $sec) = split(/[T:-]+/, $times[1]);
$time_tool = timelocal($sec, $min, $hour, $day, $month - 1);

cmp_ok(
   $time_ts - $time_tool, 'le', 1,
   "Test 2: Print delay is not expected when buffering is disabled"
) or diag($output); 

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
