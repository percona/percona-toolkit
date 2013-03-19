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

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

# #############################################################################
# Issue 360: mk-query-digest first_seen and last_seen not automatically
# populated
# #############################################################################

my $pid_file = "/tmp/pt-query-digest-test-issue_360.t.$PID";

# Need a clean query review table.
$sb->create_dbs($dbh, [qw(test percona_schema)]);

# Run pt-query-digest in the background for 2s,
# saving queries to test.query_review.
diag(`$trunk/bin/pt-query-digest --processlist h=127.1,P=12345,u=msandbox,p=msandbox --interval 0.01 --create-review-table --review h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=query_review --daemonize --pid $pid_file --log /dev/null --run-time 2`);

# Wait until its running.
PerconaTest::wait_for_files($pid_file);

# Execute some queries to give it something to see.
for (1..3) {
   $dbh->selectall_arrayref("SELECT SLEEP(1)");
}

# Wait until it stops running (should already be done).
wait_until(sub { !-e $pid_file });

my @ts = $dbh->selectrow_array('SELECT first_seen, last_seen FROM test.query_review LIMIT 1');
isnt(
   $ts[0],
   '0000-00-00 00:00:00',
   'first_seen from --processlist is not 0000-00-00 00:00:00'
);

isnt(
   $ts[1],
   '0000-00-00 00:00:00',
   'last_seen from --processlist is not 0000-00-00 00:00:00'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
