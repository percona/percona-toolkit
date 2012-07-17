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

use ReportFormatter;
use Transformers;
use DSNParser;
use Sandbox;
use CompareQueryTimes;
use PerconaTest;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}
else {
   plan tests => 25;
}

$sb->create_dbs($dbh, ['test']);

Transformers->import(qw(make_checksum));

my $ct;
my $report;
my $hosts = [
   { dbh => $dbh, name => 'server1' },
   { dbh => $dbh, name => 'server2' },
];

sub get_id {
   return make_checksum(@_);
}

# #############################################################################
# Test it.
# #############################################################################

# diag(`/tmp/12345/use < samples/compare-warnings.sql`);

$ct = new CompareQueryTimes(
   get_id => \&get_id,
);

isa_ok($ct, 'CompareQueryTimes');

# #############################################################################
# Test query time comparison.
# #############################################################################
sub compare {
   my ( $t1, $t2 ) = @_;
   return $ct->compare(
      events => [
         { fingerprint => 'foo', Query_time => $t1, },
         { fingerprint => 'foo', Query_time => $t2, },
      ],
   );
}

sub test_compare_query_times {
   my ( $t1, $t2, $diff, $comment ) = @_;
   my %diff = compare($t1, $t2);
   my $msg  = sprintf("compare t %.6f vs. %.6f %s",
      $t1, $t2, ($comment || ''));
   is(
      $diff{different_query_times},
      $diff,
      $msg,
   );
}

test_compare_query_times(0, 0, 0);
test_compare_query_times(0, 0.000001, 1, 'increase from zero');
test_compare_query_times(0.000001, 0.000005, 0, 'no increase in bucket');
test_compare_query_times(0.000001, 0.000010, 1, '1 bucket diff on edge');
test_compare_query_times(0.000008, 0.000018, 1, '1 bucket diff');
test_compare_query_times(0.000001, 10, 1, 'full bucket range diff on edges');
test_compare_query_times(0.000008, 1000000, 1, 'huge diff');

# Thresholds
test_compare_query_times(0.000001, 0.000006, 1, '1us threshold');
test_compare_query_times(0.000010, 0.000020, 1, '10us threshold');
test_compare_query_times(0.000100, 0.000200, 1, '100us threshold');
test_compare_query_times(0.001000, 0.006000, 1, '1ms threshold');
test_compare_query_times(0.010000, 0.015000, 1, '10ms threshold');
test_compare_query_times(0.100000, 0.150000, 1, '100ms threshold');
test_compare_query_times(1.000000, 1.200000, 1, '1s threshold');
test_compare_query_times(10.0,     10.1,     1, '10s threshold');

# #############################################################################
# Test the main actions, which don't do much.
# #############################################################################
my $event = {
   fingerprint => 'set @a=?',
   arg         => 'set @a=3',
   sampleno    => 4,
};

$dbh->do('set @a=1');
is_deeply(
   $dbh->selectcol_arrayref('select @a'),
   [1],
   '@a set'
);

is_deeply(
   $ct->before_execute(event => $event),
   $event,
   "before_execute() doesn't modify event"
);

$ct->execute(event => $event, dbh => $dbh);

ok(
   exists $event->{Query_time}
   && $event->{Query_time} >= 0,
   'execute() set Query_time'
);

is_deeply(
   $dbh->selectcol_arrayref('select @a'),
   [3],
   'Query was actually executed'
);

is_deeply(
   $ct->after_execute(event => $event),
   $event,
   "after_execute() doesn't modify event"
);


# #############################################################################
# Test the reports.
# #############################################################################
$ct->reset();
compare(0.000100, 0.000250);

$report = <<EOF;
# Significant query time differences
# Query ID           host1 host2 %Increase %Threshold
# ================== ===== ===== ========= ==========
# EDEF654FCCC4A4D8-0 100us 250us    150.00        100
EOF

is(
   $ct->report(hosts => $hosts),
   $report,
   'report in bucket difference'
);

$ct->reset();
compare(0.000100, 1.100251);

$report = <<EOF;
# Big query time differences
# Query ID           host1 host2 Difference
# ================== ===== ===== ==========
# EDEF654FCCC4A4D8-0 100us    1s         1s
EOF

is(
   $ct->report(hosts => $hosts),
   $report,
   'report in bucket difference'
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $ct->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
