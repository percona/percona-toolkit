#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use QueryHistory;

use TableParser;
use Quoter;
use OptionParser;
use DSNParser;
use Sandbox;
use PerconaTest;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master', {no_lc=>1});

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}

$sb->create_dbs($dbh, ['test']);
$sb->load_file('master', "t/lib/samples/query_review.sql");
my $output = "";
my $tp = new TableParser(Quoter => 'Quoter');
my $opt_parser = new OptionParser( description => 'QueryHistory tests' );
my $pat = $opt_parser->read_para_after("$trunk/bin/pt-query-digest", qr/\bMAGIC_history_columns\b/);
$pat    =~ s/\s+//g;
$pat    = qr/^(.*?)_($pat)$/;

my $qh = QueryHistory->new(
      history_dbh    => $dbh,
      column_pattern => $pat,
);

isa_ok($qh, 'QueryHistory');


# ##############################################################################
# Test review history stuff
# ##############################################################################
my $create_table = $opt_parser->read_para_after(
   "$trunk/bin/pt-query-digest", qr/MAGIC_create_history_table/);
$create_table =~ s/query_history/test.query_review_history/;
$dbh->do($create_table);
my $hist_struct = $tp->parse(
   $tp->get_create_table($dbh, 'test', 'query_review_history'));

$qh->set_history_options(
   table      => 'test.query_review_history',
   tbl_struct => $hist_struct,
);

$qh->set_review_history(
   'foo',
   'foo sample',
   Query_time => {
      pct    => 1/3,
      sum    => '0.000682',
      cnt    => 1,
      min    => '0.000682',
      max    => '0.000682',
      avg    => '0.000682',
      median => '0.000682',
      stddev => 0,
      pct_95 => '0.000682',
   },
   ts => {
      min => '090101 12:39:12',
      max => '090101 13:19:12',
      cnt => 1,
   },
);

my $res = $dbh->selectall_arrayref(
   'SELECT Lock_time_median, Lock_time_stddev, Query_time_sum, checksum, Rows_examined_stddev, ts_cnt, sample, Rows_examined_median, Rows_sent_min, Rows_examined_min, Rows_sent_sum,  Query_time_min, Query_time_pct_95, Rows_examined_sum, Rows_sent_stddev, Rows_sent_pct_95, Query_time_max, Rows_examined_max, Query_time_stddev, Rows_sent_median, Lock_time_pct_95, ts_min, Lock_time_min, Lock_time_max, ts_max, Rows_examined_pct_95 ,Rows_sent_max, Query_time_median, Lock_time_sum
   FROM test.query_review_history',
   { Slice => {} });
is_deeply(
   $res,
   [  {  checksum          => '17145033699835028696',
         sample            => 'foo sample',
         ts_min            => '2009-01-01 12:39:12',
         ts_max            => '2009-01-01 13:19:12',
         ts_cnt            => 1,
         Query_time_sum    => '0.000682',
         Query_time_min    => '0.000682',
         Query_time_max    => '0.000682',
         Query_time_median => '0.000682',
         Query_time_stddev => 0,
         Query_time_pct_95 => '0.000682',
         Lock_time_sum        => undef,
         Lock_time_min        => undef,
         Lock_time_max        => undef,
         Lock_time_pct_95     => undef,
         Lock_time_stddev     => undef,
         Lock_time_median     => undef,
         Rows_sent_sum        => undef,
         Rows_sent_min        => undef,
         Rows_sent_max        => undef,
         Rows_sent_pct_95     => undef,
         Rows_sent_stddev     => undef,
         Rows_sent_median     => undef,
         Rows_examined_sum    => undef,
         Rows_examined_min    => undef,
         Rows_examined_max    => undef,
         Rows_examined_pct_95 => undef,
         Rows_examined_stddev => undef,
         Rows_examined_median => undef,
      },
   ],
   'Review history information is in the DB',
);

eval {
   $qh->set_review_history(
      'foo',
      'foo sample',
      ts => {
         min => undef,
         max => undef,
         cnt => 1,
      },
   );
};
is($EVAL_ERROR, '', 'No error on undef ts_min and ts_max');

# #############################################################################
# Issue 1265: mk-query-digest --review-history table with minimum 2 columns
# #############################################################################
$dbh->do('truncate table test.query_review');
$dbh->do('drop table test.query_review_history');
# mqd says "The table must have at least the following columns:"
my $min_tbl = "CREATE TABLE query_review_history (
  checksum     BIGINT UNSIGNED NOT NULL,
  sample       TEXT NOT NULL
)";
$dbh->do($min_tbl);

$hist_struct = $tp->parse(
   $tp->get_create_table($dbh, 'test', 'query_review_history'));
$qh->set_history_options(
   table      => 'test.query_review_history',
   tbl_struct => $hist_struct,
);
eval {
   $qh->set_review_history(
      'foo',
      'foo sample',
      Query_time => {
         pct    => 1/3,
         sum    => '0.000682',
         cnt    => 1,
         min    => '0.000682',
         max    => '0.000682',
         avg    => '0.000682',
         median => '0.000682',
         stddev => 0,
         pct_95 => '0.000682',
      },
      ts => {
         min => '090101 12:39:12',
         max => '090101 13:19:12',
         cnt => 1,
      },
   );
};
is(
   $EVAL_ERROR,
   "",
   "Minimum 2-column review history table (issue 1265)"
);

# #############################################################################
# Done.
# #############################################################################
{
   local *STDERR;
   open STDERR, '>', \$output;
   $qh->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
