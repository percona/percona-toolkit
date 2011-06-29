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

use MaatkitTest;
use Sandbox;
shift @INC;  # These two shifts are required for tools that use base and
shift @INC;  # derived classes.  See mk-query-digest/t/101_slowlog_analyses.t
shift @INC;
require "$trunk/bin/pt-query-advisor";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 4;
}

my $output = "";
my $cnf    = "/tmp/12345/my.sandbox.cnf";
my @args   = (qw(--print-all --report-format full --group-by none --review), "F=$cnf,D=test,t=query_review");

my $review_tbl = "CREATE TABLE query_review (
  checksum     BIGINT UNSIGNED NOT NULL PRIMARY KEY,
  fingerprint  TEXT NOT NULL,
  sample       TEXT NOT NULL,
  first_seen   DATETIME,
  last_seen    DATETIME,
  reviewed_by  VARCHAR(20),
  reviewed_on  DATETIME,
  comments     TEXT
)";

$dbh->do('drop database if exists `test`');
$dbh->do('create database `test`');
$dbh->do('use `test`');
$dbh->do($review_tbl);

# Make sure it handles an empty review table.
$output = output(
      sub { pt_query_advisor::main(@args) },
);
is(
   $output,
   "",
   "Empty --review table"
);

$dbh->do('insert into test.query_review values
   (1, "select * from tbl where id=? order by col",
       "select * from tbl where id=42 order by col",
       NOW(), NOW(), NULL, NULL, NULL)');

ok(
   no_diff(
      sub { pt_query_advisor::main(@args) },
      "t/pt-query-advisor/samples/review001.txt",
   ),
   "--review with one bad query"
);

$dbh->do('insert into test.query_review values
   (2, "select col from tbl2 where id=? order by col limit ?",
       "select col from tbl2 where id=52 order by col limit 10",
       NOW(), NOW(), NULL, NULL, NULL)');

ok(
   no_diff(
      sub { pt_query_advisor::main(@args) },
      "t/pt-query-advisor/samples/review002.txt",
   ),
   "--review with 1 bad, 1 good query"
);

# That that --where works.
ok(
   no_diff(
      sub { pt_query_advisor::main(@args, qw(--where checksum=1)) },
      "t/pt-query-advisor/samples/review001.txt",
   ),
   "--review with --where"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
