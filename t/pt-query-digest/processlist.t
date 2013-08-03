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
require "$trunk/bin/pt-query-digest";

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my @args = qw(-F /tmp/12345/my.sandbox.cnf --processlist h=127.1 --report-format query_report);

system("/tmp/12345/use -e 'select sleep(3)' >/dev/null 2>&1 &");
system("/tmp/12345/use -e 'select sleep(4)' >/dev/null 2>&1 &");
system("/tmp/12345/use -e 'select sleep(5)' >/dev/null 2>&1 &");

sleep 1;

my $rows = $dbh->selectall_arrayref("show processlist");
my $exec = grep { ($_->[6] || '') =~ m/executing|sleep/ } @$rows;
is(
   $exec,
   3,
   "Three queries are executing"
) or print Dumper($rows);

my $output = output(
   sub { pt_query_digest::main(@args, qw(--run-time 5)); },
);

($exec) = $output =~ m/^(# Exec time.+?)$/ms;
# The end of the line is like "786ms      3s".  The 2nd to last value is
# stddev which can vary slightly depending on the real exec time.  The
# other int values should always round to the correct values.  786ms is
# the usual stddev. -- stddev doesn't matter much.  It's the other vals
# that indicate that --processlist works.
$exec =~ s/(\S+)      3s$/786ms      3s/;
ok(
   no_diff(
      $exec,
      "t/pt-query-digest/samples/proclist001.txt",
      cmd_output => 1,
   ),
   "--processlist correctly observes and measures multiple queries"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
