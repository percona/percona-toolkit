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
use SqlModes;
require "$trunk/bin/pt-query-digest";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

sub normalize_numbers {
   use Scalar::Util qw(looks_like_number);
   my $AoH = shift;
   for my $h (@$AoH) {
      $_ = sprintf("%.8f", $_) for grep { looks_like_number($_) } values %$h;
   }
}

sub run_with {
   my ($file, @args) = @_;
   $file = "$trunk/t/lib/samples/slowlogs/$file";
   
   return output(sub{
      pt_query_digest::main(qw(--report-format=query_report),
                            qw(--limit 10), @args, $file)
   }, stderr => 1);
}

my $dsn      = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my $output;
my $cmd;

$sb->create_dbs($dbh, ['test']);
$sb->load_file('master', 't/pt-query-digest/samples/query_review.sql');

# Test --create-review
$output = run_with("slow006.txt", qw(--create-review-table),
                '--review', "$dsn,D=test,t=query_review");

my ($table) = $dbh->selectrow_array(
   "show tables from test like 'query_review'");
# 1
is($table, 'query_review', '--create-review-table');

$output = run_with("slow006.txt",
                   '--review', "$dsn,D=test,t=query_review" );
my $res = $dbh->selectall_arrayref( 'SELECT * FROM test.query_review',
   { Slice => {} } );

my $expected = [
  {
    checksum => '3E4FB43148C4B07CD4CD74934382A184',
    comments => undef,
    fingerprint => 'select col from bar_tbl',
    first_seen => '2007-12-18 11:48:57',
    last_seen => '2007-12-18 11:49:07',
    reviewed_by => undef,
    reviewed_on => undef,
    sample => 'SELECT col FROM bar_tbl'
  },
  {
    checksum => '538CA093E701E0CBA20C29AF174CE545',
    comments => undef,
    fingerprint => 'select col from foo_tbl',
    first_seen => '2007-12-18 11:48:27',
    last_seen => '2007-12-18 11:49:30',
    reviewed_by => undef,
    reviewed_on => undef,
    sample => 'SELECT col FROM foo_tbl'
  }
];

normalize_numbers($res);
   
# 2
is_deeply(
   $res,
   $expected,
   'Adds/updates queries to query review table'
);

# This time we'll run with --report and since none of the queries
# have been reviewed, the report should include both of them with
# their respective query review info added to the report.
$output = run_with("slow006.txt",
                   '--review', "$dsn,D=test,t=query_review" );
# 3
ok(
   no_diff($output, "t/pt-query-digest/samples/slow006_AR_1.txt", cmd_output => 1),
   'Analyze-review pass 1 reports not-reviewed queries'
);

# Mark a query as reviewed and run --report again and that query should
# not be reported.
$dbh->do('UPDATE test.query_review
   SET reviewed_by="daniel", reviewed_on="2008-12-24 12:00:00", comments="foo_tbl is ok, so are cranberries"
   WHERE checksum="11676753765851784517"');
$output = run_with("slow006.txt",
                   '--review', "$dsn,D=test,t=query_review");
# 4
ok(
   no_diff($output, "t/pt-query-digest/samples/slow006_AR_2.txt", cmd_output => 1),
   'Analyze-review pass 2 does not report the reviewed query'
);

# And a 4th pass with --report-all which should cause the reviewed query
# to re-appear in the report with the reviewed_by, reviewed_on and comments
# info included.
$output = run_with("slow006.txt", '--report-all',
                   '--review', "$dsn,D=test,t=query_review");
ok(
   no_diff($output, "t/pt-query-digest/samples/slow006_AR_4.txt", cmd_output => 1),
   'Analyze-review pass 4 with --report-all reports reviewed query'
);

# Test that reported review info gets all meta-columns dynamically.
$dbh->do('ALTER TABLE test.query_review ADD COLUMN foo INT');
$dbh->do('UPDATE test.query_review
   SET foo=42 WHERE checksum="15334040482108055940"');

$output = run_with("slow006.txt",
                   '--review', "$dsn,D=test,t=query_review");
ok(
   no_diff($output, "t/pt-query-digest/samples/slow006_AR_5.txt", cmd_output => 1),
   'Analyze-review pass 5 reports new review info column'
);

# Make sure that when we run with all-0 timestamps they don't show up in the
# output because they are useless of course (issue 202).

SKIP: {
    skip "MySQL 5.7 doesn't allow '0000-00-00' dates" if ($sandbox_version ge '5.7');
    # Since some sql_modes don't allow '0000-00-00' dates, to keep this test valid
    # we simply remove them for a moment and then restore.
    my $modes = new SqlModes($dbh);
    $modes->del(qw(STRICT_TRANS_TABLES STRICT_ALL_TABLES NO_ZERO_IN_DATE NO_ZERO_DATE));
    
    my $currmodes = $modes->get_modes_string();
    
    $dbh->do("update test.query_review set first_seen='0000-00-00 00:00:00', "
       . " last_seen='0000-00-00 00:00:00'");
    $output = run_with("slow022.txt",
                       '--review', "$dsn,D=test,t=query_review");
    unlike($output, qr/last_seen/, 'no last_seen when 0000 timestamp');
    unlike($output, qr/first_seen/, 'no first_seen when 0000 timestamp');
    unlike($output, qr/0000-00-00 00:00:00/, 'no 0000-00-00 00:00:00 timestamp');
    
    $modes->restore_original_modes();
}

# ##########################################################################
# XXX The following tests will cause non-deterministic data, so run them
# after anything that wants to check the contents of the --review table.
# ##########################################################################

# Make sure a missing Time property does not cause a crash.  Don't test data
# in table, because it varies based on when you run the test.
$output = run_with("slow021.txt",
                   '--review', "$dsn,D=test,t=query_review");

unlike($output, qr/Use of uninitialized value/, 'didnt crash due to undef ts');

# Make sure a really ugly Time property that doesn't parse does not cause a
# crash.  Don't test data in table, because it varies based on when you run
# the test.
$output = run_with("slow022.txt",
                   '--review', "$dsn,D=test,t=query_review");

# Don't test data in table, because it varies based on when you run the test.
unlike($output, qr/Use of uninitialized value/, 'no crash due to totally missing ts');

# #############################################################################
# --review --no-report
# #############################################################################
$sb->load_file('master', 't/pt-query-digest/samples/query_review.sql');
$output = run_with("slow006.txt", '--no-report',
                   '--review', "$dsn,D=test,t=query_review");

$res = $dbh->selectall_arrayref('SELECT * FROM test.query_review');
is(
   $res->[0]->[1],
   'select col from bar_tbl',
   "--review works with --no-report"
);
is(
   $output,
   '',
   'No output with --review and --no-report'
);


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
