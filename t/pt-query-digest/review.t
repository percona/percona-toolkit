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
shift @INC;
shift @INC;
shift @INC;
require "$trunk/bin/pt-query-digest";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 17;
}

my $run_with = "$trunk/bin/pt-query-digest --report-format=query_report --limit 10 $trunk/t/lib/samples/slowlogs/";
my $output;
my $cmd;

$sb->create_dbs($dbh, ['test']);
$sb->load_file('master', 't/pt-query-digest/samples/query_review.sql');

# Test --create-review and --create-review-history-table
$output = 'foo'; # clear previous test results
$cmd = "${run_with}slow006.txt --create-review-table --review "
   . "h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=query_review --create-review-history-table "
   . "--review-history t=query_review_history";
$output = `$cmd >/dev/null 2>&1`;

my ($table) = $dbh->selectrow_array(
   'show tables from test like "query_review"');
is($table, 'query_review', '--create-review');
($table) = $dbh->selectrow_array(
   'show tables from test like "query_review_history"');
is($table, 'query_review_history', '--create-review-history-table');

$output = 'foo'; # clear previous test results
$cmd = "${run_with}slow006.txt --review h=127.1,u=msandbox,p=msandbox,P=12345,D=test,t=query_review "
   . "--review-history t=query_review_history";
$output = `$cmd`;
my $res = $dbh->selectall_arrayref( 'SELECT * FROM test.query_review',
   { Slice => {} } );
is_deeply(
   $res,
   [  {  checksum    => '11676753765851784517',
         reviewed_by => undef,
         reviewed_on => undef,
         last_seen   => '2007-12-18 11:49:30',
         first_seen  => '2007-12-18 11:48:27',
         sample      => 'SELECT col FROM foo_tbl',
         fingerprint => 'select col from foo_tbl',
         comments    => undef,
      },
      {  checksum    => '15334040482108055940',
         reviewed_by => undef,
         reviewed_on => undef,
         last_seen   => '2007-12-18 11:49:07',
         first_seen  => '2007-12-18 11:48:57',
         sample      => 'SELECT col FROM bar_tbl',
         fingerprint => 'select col from bar_tbl',
         comments    => undef,
      },
   ],
   'Adds/updates queries to query review table'
);
$res = $dbh->selectall_arrayref('SELECT lock_time_median, lock_time_stddev, query_time_sum, checksum, rows_examined_stddev, ts_cnt, sample, rows_examined_median, rows_sent_min, rows_examined_min, rows_sent_sum,  query_time_min, query_time_pct_95, rows_examined_sum, rows_sent_stddev, rows_sent_pct_95, query_time_max, rows_examined_max, query_time_stddev, rows_sent_median, lock_time_pct_95, ts_min, lock_time_min, lock_time_max, ts_max, rows_examined_pct_95 ,rows_sent_max, query_time_median, lock_time_sum FROM test.query_review_history',
   { Slice => {} } );
is_deeply(
   $res,
   [  {  lock_time_median     => '0',
         lock_time_stddev     => '0',
         query_time_sum       => '3.6e-05',
         checksum             => '11676753765851784517',
         rows_examined_stddev => '0',
         ts_cnt               => '3',
         sample               => 'SELECT col FROM foo_tbl',
         rows_examined_median => '0',
         rows_sent_min        => '0',
         rows_examined_min    => '0',
         rows_sent_sum        => '0',
         query_time_min       => '1.2e-05',
         query_time_pct_95    => '1.2e-05',
         rows_examined_sum    => '0',
         rows_sent_stddev     => '0',
         rows_sent_pct_95     => '0',
         query_time_max       => '1.2e-05',
         rows_examined_max    => '0',
         query_time_stddev    => '0',
         rows_sent_median     => '0',
         lock_time_pct_95     => '0',
         ts_min               => '2007-12-18 11:48:27',
         lock_time_min        => '0',
         lock_time_max        => '0',
         ts_max               => '2007-12-18 11:49:30',
         rows_examined_pct_95 => '0',
         rows_sent_max        => '0',
         query_time_median    => '1.2e-05',
         lock_time_sum        => '0'
      },
      {  lock_time_median     => '0',
         lock_time_stddev     => '0',
         query_time_sum       => '3.6e-05',
         checksum             => '15334040482108055940',
         rows_examined_stddev => '0',
         ts_cnt               => '3',
         sample               => 'SELECT col FROM bar_tbl',
         rows_examined_median => '0',
         rows_sent_min        => '0',
         rows_examined_min    => '0',
         rows_sent_sum        => '0',
         query_time_min       => '1.2e-05',
         query_time_pct_95    => '1.2e-05',
         rows_examined_sum    => '0',
         rows_sent_stddev     => '0',
         rows_sent_pct_95     => '0',
         query_time_max       => '1.2e-05',
         rows_examined_max    => '0',
         query_time_stddev    => '0',
         rows_sent_median     => '0',
         lock_time_pct_95     => '0',
         ts_min               => '2007-12-18 11:48:57',
         lock_time_min        => '0',
         lock_time_max        => '0',
         ts_max               => '2007-12-18 11:49:07',
         rows_examined_pct_95 => '0',
         rows_sent_max        => '0',
         query_time_median    => '1.2e-05',
         lock_time_sum        => '0'
      }
   ],
   'Adds/updates queries to query review history table'
);

# This time we'll run with --report and since none of the queries
# have been reviewed, the report should include both of them with
# their respective query review info added to the report.
ok(
   no_diff($run_with.'slow006.txt --review h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=query_review', "t/pt-query-digest/samples/slow006_AR_1.txt"),
   'Analyze-review pass 1 reports not-reviewed queries'
);

# Mark a query as reviewed and run --report again and that query should
# not be reported.
$dbh->do('UPDATE test.query_review
   SET reviewed_by="daniel", reviewed_on="2008-12-24 12:00:00", comments="foo_tbl is ok, so are cranberries"
   WHERE checksum=11676753765851784517');
ok(
   no_diff($run_with.'slow006.txt --review h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=query_review', "t/pt-query-digest/samples/slow006_AR_2.txt"),
   'Analyze-review pass 2 does not report the reviewed query'
);

# And a 4th pass with --report-all which should cause the reviewed query
# to re-appear in the report with the reviewed_by, reviewed_on and comments
# info included.
ok(
   no_diff($run_with.'slow006.txt --review h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=query_review   --report-all', "t/pt-query-digest/samples/slow006_AR_4.txt"),
   'Analyze-review pass 4 with --report-all reports reviewed query'
);

# Test that reported review info gets all meta-columns dynamically.
$dbh->do('ALTER TABLE test.query_review ADD COLUMN foo INT');
$dbh->do('UPDATE test.query_review
   SET foo=42 WHERE checksum=15334040482108055940');
ok(
   no_diff($run_with.'slow006.txt --review h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=query_review', "t/pt-query-digest/samples/slow006_AR_5.txt"),
   'Analyze-review pass 5 reports new review info column'
);

# Make sure that when we run with all-0 timestamps they don't show up in the
# output because they are useless of course (issue 202).
$dbh->do("update test.query_review set first_seen='0000-00-00 00:00:00', "
   . " last_seen='0000-00-00 00:00:00'");
$output = 'foo'; # clear previous test results
$cmd = "${run_with}slow022.txt --review h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=query_review"; 
$output = `$cmd`;
unlike($output, qr/last_seen/, 'no last_seen when 0000 timestamp');
unlike($output, qr/first_seen/, 'no first_seen when 0000 timestamp');
unlike($output, qr/0000-00-00 00:00:00/, 'no 0000-00-00 00:00:00 timestamp');

# ##########################################################################
# XXX The following tests will cause non-deterministic data, so run them
# after anything that wants to check the contents of the --review table.
# ##########################################################################

# Make sure a missing Time property does not cause a crash.  Don't test data
# in table, because it varies based on when you run the test.
$output = 'foo'; # clear previous test results
$cmd = "${run_with}slow021.txt --review h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=query_review"; 
$output = `$cmd`;
unlike($output, qr/Use of uninitialized value/, 'didnt crash due to undef ts');

# Make sure a really ugly Time property that doesn't parse does not cause a
# crash.  Don't test data in table, because it varies based on when you run
# the test.
$output = 'foo'; # clear previous test results
$cmd = "${run_with}slow022.txt --review h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=query_review"; 
$output = `$cmd`;
# Don't test data in table, because it varies based on when you run the test.
unlike($output, qr/Use of uninitialized value/, 'no crash due to totally missing ts');

# #############################################################################
# --review --no-report
# #############################################################################
$sb->load_file('master', 't/pt-query-digest/samples/query_review.sql');
$output = `${run_with}slow006.txt --review h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=query_review --no-report --create-review-table`;
$res = $dbh->selectall_arrayref('SELECT * FROM test.query_review');
is(
   $res->[0]->[1],
   'select col from foo_tbl',
   "--review works with --no-report"
);
is(
   $output,
   '',
   'No output with --review and --no-report'
);


# #############################################################################
# Issue 1149: Add Percona attributes to mk-query-digest review table
# #############################################################################
$dbh->do('truncate table test.query_review');
$dbh->do('truncate table test.query_review_history');

`${run_with}slow002.txt --review h=127.1,u=msandbox,p=msandbox,P=12345,D=test,t=query_review --review-history t=query_review_history --no-report --filter '\$event->{arg} =~ m/foo\.bar/' > /dev/null`;

$res = $dbh->selectall_arrayref( 'SELECT * FROM test.query_review_history',
   { Slice => {} } );

is_deeply(
   $res,
   [
      {
         sample => "UPDATE foo.bar
SET    biz = '91848182522'",
         checksum => '12831241509574346332',
         filesort_on_disk_cnt => '2',
         filesort_on_disk_sum => '0',
         tmp_table_on_disk_cnt => '2',
         tmp_table_on_disk_sum => '0',
         filesort_cnt => '2',
         filesort_sum => '0',
         full_join_cnt => '2',
         full_join_sum => '0',
         full_scan_cnt => '2',
         full_scan_sum => '0',
         innodb_io_r_bytes_max => 0,
         innodb_io_r_bytes_median => 0,
         innodb_io_r_bytes_min => 0,
         innodb_io_r_bytes_pct_95 => 0,
         innodb_io_r_bytes_stddev => 0,
         innodb_io_r_ops_max => 0,
         innodb_io_r_ops_median => 0,
         innodb_io_r_ops_min => 0,
         innodb_io_r_ops_pct_95 => 0,
         innodb_io_r_ops_stddev => 0,
         innodb_io_r_wait_max => 0,
         innodb_io_r_wait_median => 0,
         innodb_io_r_wait_min => 0,
         innodb_io_r_wait_pct_95 => 0,
         innodb_io_r_wait_stddev => 0,
         innodb_pages_distinct_max => 18,
         innodb_pages_distinct_median => 18,
         innodb_pages_distinct_min => 18,
         innodb_pages_distinct_pct_95 => 18,
         innodb_pages_distinct_stddev => 0,
         innodb_queue_wait_max => 0,
         innodb_queue_wait_median => 0,
         innodb_queue_wait_min => 0,
         innodb_queue_wait_pct_95 => 0,
         innodb_queue_wait_stddev => 0,
         innodb_rec_lock_wait_max => 0,
         innodb_rec_lock_wait_median => 0,
         innodb_rec_lock_wait_min => 0,
         innodb_rec_lock_wait_pct_95 => 0,
         innodb_rec_lock_wait_stddev => 0,
         lock_time_max => '2.7e-05',
         lock_time_median => '2.7e-05',
         lock_time_min => '2.7e-05',
         lock_time_pct_95 => '2.7e-05',
         lock_time_stddev => '0',
         lock_time_sum => '5.4e-05',
         merge_passes_max => '0',
         merge_passes_median => '0',
         merge_passes_min => '0',
         merge_passes_pct_95 => '0',
         merge_passes_stddev => '0',
         merge_passes_sum => '0',
         qc_hit_cnt => '2',
         qc_hit_sum => '0',
         query_time_max => 0.000530,
         query_time_median => 0.000530,
         query_time_min => 0.000530,
         query_time_pct_95 => 0.000530,
         query_time_stddev => 0,
         query_time_sum => 0.000530 * 2,
         rows_affected_max => undef,
         rows_affected_median => undef,
         rows_affected_min => undef,
         rows_affected_pct_95 => undef,
         rows_affected_stddev => undef,
         rows_affected_sum => undef,
         rows_examined_max => 0,
         rows_examined_median => 0,
         rows_examined_min => 0,
         rows_examined_pct_95 => 0,
         rows_examined_stddev => 0,
         rows_examined_sum => 0,
         rows_read_max => undef,
         rows_read_median => undef,
         rows_read_min => undef,
         rows_read_pct_95 => undef,
         rows_read_stddev => undef,
         rows_read_sum => undef,
         rows_sent_max => '0',
         rows_sent_median => '0',
         rows_sent_min => '0',
         rows_sent_pct_95 => '0',
         rows_sent_stddev => '0',
         rows_sent_sum => '0',
         tmp_table_cnt => '2',
         tmp_table_sum => '0',
         ts_cnt => 2,
         ts_max => '2007-12-18 11:48:27',
         ts_min => '2007-12-18 11:48:27',
      },
   ],
   "Review history has Percona extended slowlog attribs (issue 1149)"
);


# #############################################################################
# Issue 1265: mk-query-digest --review-history table with minimum 2 columns
# #############################################################################
$dbh->do('use test');
$dbh->do('truncate table test.query_review');
$dbh->do('drop table test.query_review_history');

# mqd says "The table must have at least the following columns:"
my $min_tbl = "CREATE TABLE query_review_history (
  checksum     BIGINT UNSIGNED NOT NULL,
  sample       TEXT NOT NULL
)";
$dbh->do($min_tbl);

$output = output(
   sub { pt_query_digest::main(
      '--review', 'h=127.1,u=msandbox,p=msandbox,P=12345,D=test,t=query_review',
      '--review-history', 't=query_review_history',
      qw(--no-report --no-continue-on-error),
      "$trunk/t/lib/samples/slow002.txt")
   },
   stderr => 1,
);

unlike(
   $output,
   qr/error/,
   "No error using minimum 2-column query review history table (issue 1265)",
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
