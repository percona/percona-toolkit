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

require "$trunk/bin/pt-query-digest";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $sample = "t/pt-query-digest/samples/";

$dbh->do('drop database if exists food');
$dbh->do('create database food');
$dbh->do('use food');
$dbh->do('create table trees (fruit varchar(24), unique index (fruit))');

my $output = '';
my @args   = ('--explain', 'h=127.1,P=12345,u=msandbox,p=msandbox,D=food', qw(--report-format=query_report --limit 10));

# The table has no rows so EXPLAIN will return NULL for most values.
ok(
   no_diff(
      sub { pt_query_digest::main(@args,
         "$trunk/t/lib/samples/slowlogs/slow007.txt") },
      ( $sandbox_version ge '5.5' ? "$sample/slow007_explain_1-55.txt"
      : $sandbox_version ge '5.1' ? "$sample/slow007_explain_1-51.txt"
      :                             "$sample/slow007_explain_1.txt")
   ),
   'Analysis for slow007 with --explain, no rows',
);

# Normalish output from EXPLAIN.
$dbh->do("insert into trees values ('apple'),('orange'),('banana')");

ok(
   no_diff(
      sub { pt_query_digest::main(@args,
         "$trunk/t/lib/samples/slowlogs/slow007.txt") },
      ($sandbox_version ge '5.1' ? "$sample/slow007_explain_2-51.txt"
                                 : "$sample/slow007_explain_2.txt")
   ),
   'Analysis for slow007 with --explain',
);

# #############################################################################
# Issue 1141: Add "spark charts" to mk-query-digest profile
# #############################################################################
ok(
   no_diff(
      sub { pt_query_digest::main(@args,
         "$trunk/t/lib/samples/slowlogs/slow007.txt", qw(--report-format profile)) },
      "$sample/slow007_explain_4.txt",
   ),
   'EXPLAIN sparkline in profile'
);

# #############################################################################
# Failed EXPLAIN.
# #############################################################################
$dbh->do('drop table trees');

ok(
   no_diff(
      sub { pt_query_digest::main(@args,
         '--report-format', 'query_report,profile',
         "$trunk/t/lib/samples/slowlogs/slow007.txt") },
      "t/pt-query-digest/samples/slow007_explain_3.txt",
      trf => "sed 's/at .* line [0-9]*/at line ?/'",
   ),
   'Analysis for slow007 with --explain, failed',
);

# #############################################################################
# Issue 1196: mk-query-digest --explain is broken
# #############################################################################
$sb->load_file('master', "t/pt-query-digest/samples/issue_1196.sql");

ok(
   no_diff(
      sub { pt_query_digest::main(@args,
         '--report-format', 'profile,query_report',
         "$trunk/t/pt-query-digest/samples/issue_1196.log",)
      },
      (  $sandbox_version eq '5.6' ? "$sample/issue_1196-output-5.6.txt"
       : $sandbox_version ge '5.1' ? "$sample/issue_1196-output.txt"
       :                             "$sample/issue_1196-output-5.0.txt"),
   ),
   "--explain sparkline uses event db and doesn't crash ea (issue 1196"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
