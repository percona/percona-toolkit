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
use DSNParser;
use Sandbox;
require VersionParser;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

if ( $sandbox_version lt '8.0') {
   plan skip_all => "Requires MySQL 8.0 or newer";
}

my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
else {
   plan tests => 3;
}

my $pid_file = "/tmp/pt-query-digest-test-pt-2264.t.$PID";
my $log_file = "/tmp/pt-query-digest-test-pt-2264.t.log";

# Need a clean query review table.
$sb->create_dbs($dbh, [qw(test percona_schema)]);

# Run pt-query-digest in the background for 2s,
# saving queries to test.query_review.
diag(`$trunk/bin/pt-query-digest --processlist h=127.1,P=12345,u=msandbox,p=msandbox --interval 0.01 --daemonize --pid $pid_file --output slowlog --log $log_file --run-time 3`);

# Wait until its running.
PerconaTest::wait_for_files($pid_file);

# Execute some queries to give it something to see.
for (1..3) {
   $dbh->selectall_arrayref("SELECT SLEEP(2), '😜'");
}

# Wait until it stops running (should already be done).
wait_until(sub { !-e $pid_file });

my $output = `cat $log_file`;

like(
   $output,
   qr/😜/,
   'Smiley character successfully printed in the output'
) or diag($output);

unlike(
   $output,
   qr/Wide character in print at/,
   'Smiley character did not cause error'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
diag(`rm $log_file`);
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
