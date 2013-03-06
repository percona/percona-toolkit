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
      for (values %$h) {
         next unless looks_like_number($_);
         $_ = sprintf("%.8f", $_)
      }
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

# Test --create-review and --create-review-history-table
$output = run_with("slow006.txt", '--create-history-table',
                "--history", "$dsn,D=test,t=query_review_history");

my ($table) = $dbh->selectrow_array(
   "show tables from test like 'query_review_history'");
is($table, 'query_review_history', '--create-history-table');

my $res = $dbh->selectall_arrayref('SELECT lock_time_median, lock_time_stddev,
FORMAT(query_time_sum, 6) AS query_time_sum, checksum,
FORMAT(rows_examined_stddev, 6) AS rows_examined_stddev, ts_cnt, sample,
FORMAT(rows_examined_median, 6) AS rows_examined_median, rows_sent_min,
rows_examined_min, rows_sent_sum, FORMAT(query_time_min, 6) AS query_time_min,
FORMAT(query_time_pct_95, 6) AS query_time_pct_95, rows_examined_sum,
FORMAT(rows_sent_stddev, 6) AS rows_sent_stddev, FORMAT(rows_sent_pct_95, 6) AS
rows_sent_pct_95, FORMAT(query_time_max, 6) AS query_time_max,
rows_examined_max, FORMAT(query_time_stddev, 6) AS query_time_stddev,
rows_sent_median, FORMAT(lock_time_pct_95, 6) AS lock_time_pct_95, ts_min,
FORMAT(lock_time_min, 6) AS lock_time_min, lock_time_max, ts_max,
FORMAT(rows_examined_pct_95, 6) AS rows_examined_pct_95, rows_sent_max,
FORMAT(query_time_median, 6) AS query_time_median, lock_time_sum FROM
test.query_review_history', { Slice => {} } );

my $expected =   [  {  lock_time_median     => '0',
         lock_time_stddev     => '0',
         query_time_sum       => '0.000036',
         checksum             => '11676753765851784517',
         rows_examined_stddev => '0.000000',
         ts_cnt               => '3',
         sample               => 'SELECT col FROM foo_tbl',
         rows_examined_median => '0.000000',
         rows_sent_min        => '0',
         rows_examined_min    => '0',
         rows_sent_sum        => '0',
         query_time_min       => '0.000012',
         query_time_pct_95    => '0.000012',
         rows_examined_sum    => '0',
         rows_sent_stddev     => '0.000000',
         rows_sent_pct_95     => '0.000000',
         query_time_max       => '0.000012',
         rows_examined_max    => '0',
         query_time_stddev    => '0.000000',
         rows_sent_median     => '0',
         lock_time_pct_95     => '0.000000',
         ts_min               => '2007-12-18 11:48:27',
         lock_time_min        => '0.000000',
         lock_time_max        => '0',
         ts_max               => '2007-12-18 11:49:30',
         rows_examined_pct_95 => '0.000000',
         rows_sent_max        => '0',
         query_time_median    => '0.000012',
         lock_time_sum        => '0'
      },
      {  lock_time_median     => '0',
         lock_time_stddev     => '0',
         query_time_sum       => '0.000036',
         checksum             => '15334040482108055940',
         rows_examined_stddev => '0.000000',
         ts_cnt               => '3',
         sample               => 'SELECT col FROM bar_tbl',
         rows_examined_median => '0.000000',
         rows_sent_min        => '0',
         rows_examined_min    => '0',
         rows_sent_sum        => '0',
         query_time_min       => '0.000012',
         query_time_pct_95    => '0.000012',
         rows_examined_sum    => '0',
         rows_sent_stddev     => '0.000000',
         rows_sent_pct_95     => '0.000000',
         query_time_max       => '0.000012',
         rows_examined_max    => '0',
         query_time_stddev    => '0.000000',
         rows_sent_median     => '0',
         lock_time_pct_95     => '0.000000',
         ts_min               => '2007-12-18 11:48:57',
         lock_time_min        => '0.000000',
         lock_time_max        => '0',
         ts_max               => '2007-12-18 11:49:07',
         rows_examined_pct_95 => '0.000000',
         rows_sent_max        => '0',
         query_time_median    => '0.000012',
         lock_time_sum        => '0'
      }
   ];

normalize_numbers($res);
normalize_numbers($expected);

is_deeply(
   $res,
   $expected,
   'Adds/updates queries to query review history table'
);


run_with("slow006.txt", '--create-history-table',
                   '--history', "$dsn");

($table) = $dbh->selectrow_array(
   "show tables from percona_schema like 'query_history'");
is($table, 'query_history', '--create-history-table creates both percona_schema and query_history');

# #############################################################################
# Issue 1149: Add Percona attributes to mk-query-digest history table
# #############################################################################
$dbh->do('truncate table test.query_review_history');

run_with("slow002.txt",
         '--history', "$dsn,D=test,t=query_review_history",
         '--no-report', '--filter', '$event->{arg} =~ m/foo\.bar/');

$res = $dbh->selectall_arrayref( 'SELECT * FROM test.query_review_history',
   { Slice => {} } );

$expected =    [
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
         lock_time_max => '0.000027',
         lock_time_median => '0.000027',
         lock_time_min => '0.000027',
         lock_time_pct_95 => '0.000027',
         lock_time_stddev => '0',
         lock_time_sum => '0.000054',
         merge_passes_max => '0',
         merge_passes_median => '0',
         merge_passes_min => '0',
         merge_passes_pct_95 => '0',
         merge_passes_stddev => '0',
         merge_passes_sum => '0',
         qc_hit_cnt => '2',
         qc_hit_sum => '0',
         query_time_max => '0.00053',
         query_time_median => '0.00053',
         query_time_min => '0.00053',
         query_time_pct_95 => '0.00053',
         query_time_stddev => '0',
         query_time_sum => '0.00106',
         rows_affected_max => undef,
         rows_affected_median => undef,
         rows_affected_min => undef,
         rows_affected_pct_95 => undef,
         rows_affected_stddev => undef,
         rows_affected_sum => undef,
         rows_examined_max => 0,
         rows_examined_median => '0',
         rows_examined_min => 0,
         rows_examined_pct_95 => '0',
         rows_examined_stddev => '0',
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
   ];

normalize_numbers($res);
normalize_numbers($expected);

is_deeply(
   $res,
   $expected,
   "Review history has Percona extended slowlog attribs (issue 1149)",
);


# #############################################################################
# Issue 1265: mk-query-digest --review-history table with minimum 2 columns
# #############################################################################
$dbh->do('use test');
$dbh->do('drop table test.query_review_history');

# mqd says "The table must have at least the following columns:"
my $min_tbl = "CREATE TABLE query_review_history (
  checksum     BIGINT UNSIGNED NOT NULL,
  sample       TEXT NOT NULL
)";
$dbh->do($min_tbl);

$output = output(
   sub { pt_query_digest::main(
      '--history', "$dsn,D=test,t=query_review_history",
      qw(--no-report --no-continue-on-error),
      "$trunk/t/lib/samples/slowlogs/slow002.txt")
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
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
