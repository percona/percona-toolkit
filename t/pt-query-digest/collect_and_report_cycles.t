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
use DSNParser;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 4;
}

my $run_with = "$trunk/bin/pt-query-digest --report-format=query_report --limit 10 $trunk/t/lib/samples/slowlogs/";

# #############################################################################
# Issue 173: Make mk-query-digest do collect-and-report cycles
# #############################################################################

# This tests --iterations by checking that its value multiplies --run-for. 
# So if --run-for is 2 and we do 2 iterations, we should run for 4 seconds
# total.
my $pid;
my $output;

system("$trunk/bin/pt-query-digest --processlist h=127.1,P=12345,u=msandbox,p=msandbox --run-time 2 --iterations 2 --port 12345 --pid /tmp/mk-query-digest.pid --daemonize 1>/dev/null 2>/dev/null");
chomp($pid = `cat /tmp/mk-query-digest.pid`);
sleep 3;
$output = `ps x | grep $pid | grep processlist | grep -v grep`;
ok(
   $output,
   'Still running for --iterations (issue 173)'
);

sleep 2;
$output = `ps x | grep $pid | grep processlist | grep -v grep`;
ok(
   !$output,
   'No longer running for --iterations (issue 173)'
);

# Another implicit test of --iterations checks that on the second
# iteration no queries are reported because the slowlog was read
# entirely by the first iteration.
ok(
   no_diff($run_with . 'slow002.txt --iterations 2   --report-format=query_report,profile --limit 1',
   "t/pt-query-digest/samples/slow002_iters_2.txt"),
   '--iterations'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
