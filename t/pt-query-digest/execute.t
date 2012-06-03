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

use Sandbox;
use PerconaTest;
use VersionParser;
# See 101_slowlog_analyses.t for why we shift.
shift @INC;  # our unshift (above)
shift @INC;  # PerconaTest's unshift
shift @INC;  # Sandbox

require "$trunk/bin/pt-query-digest";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $vp  = new VersionParser();
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 7;
}

my $output = '';
my $cnf    = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args   = qw(--report-format=query_report --limit 10 --stat);

$sb->create_dbs($dbh, [qw(test)]);
$dbh->do('use test');
$dbh->do('create table foo (a int, b int, c int)');

is_deeply(
   $dbh->selectall_arrayref('select * from test.foo'),
   [],
   'No rows in table yet'
);

ok(
   no_diff(
      sub { pt_query_digest::main(@args, '--execute', $cnf,
         "$trunk/t/lib/samples/slowlogs/slow018.txt") },
      't/pt-query-digest/samples/slow018_execute_report_1.txt',
   ),
   '--execute without database'
);

is_deeply(
   $dbh->selectall_arrayref('select * from test.foo'),
   [],
   'Still no rows in table'
);

# Provide a default db to make --execute work.
$cnf .= ',D=test';

# TODO: This test is a PITA because every time the mqd output
# changes the -n of tail has to be adjusted.

# 

# We tail to get everything from "Exec orig" onward.  The lines
# above have the real execution time will will vary.  The last 18 lines
# are sufficient to see that it actually executed without errors.
ok(
   no_diff(
      sub { pt_query_digest::main(@args, '--execute', $cnf,
         "$trunk/t/lib/samples/slowlogs/slow018.txt") },
      't/pt-query-digest/samples/slow018_execute_report_2.txt',
      trf => 'tail -n 30',
      sed => ["-e 's/s  ##*/s/g'"],
   ),
   '--execute with default database'
);

is_deeply(
   $dbh->selectall_arrayref('select * from test.foo'),
   [[qw(1 2 3)],[qw(4 5 6)]],
   'Rows in table'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
