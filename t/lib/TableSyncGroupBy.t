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
use Data::Dumper;

use TableSyncGroupBy;
use Quoter;
use MockSth;
use RowDiff;
use ChangeHandler;
use PerconaTest;

my $q = new Quoter();
my $tbl_struct = {
   type_for => { a => 'int', b => 'int', c => 'int' },
   col_posn => { a => 1, b => 2, c => 3 },
   is_col   => { a => 1, b => 2, c => 3 },
};
my @rows;

throws_ok(
   sub { new TableSyncGroupBy() },
   qr/I need a Quoter/,
   'Quoter required'
);
my $t = new TableSyncGroupBy(
   Quoter => $q,
);

my $ch = new ChangeHandler(
   Quoter    => $q,
   right_db  => 'test',
   right_tbl => 'foo',
   left_db   => 'test',
   left_tbl  => 'foo',
   replace   => 0,
   actions   => [ sub { push @rows, $_[0] }, ],
   queue     => 0,
   tbl_struct => $tbl_struct,
);

$t->prepare_to_sync(
   ChangeHandler => $ch,
   cols          => [qw(a b c)],
   tbl_struct    => $tbl_struct,
   buffer_in_mysql => 1,
);
is(
   $t->get_sql(
      where    => 'foo=1',
      database => 'test',
      table    => 'foo',
   ),
   'SELECT SQL_BUFFER_RESULT `a`, `b`, `c`, COUNT(*) AS __maatkit_count FROM `test`.`foo` '
      . 'WHERE foo=1 GROUP BY `a`, `b`, `c` ORDER BY `a`, `b`, `c`',
   'Got SQL with SQL_BUFFER_RESULT',
);

$t->prepare_to_sync(
   ChangeHandler => $ch,
   cols          => [qw(a b c)],
   tbl_struct    => $tbl_struct,
);
is(
   $t->get_sql(
      where    => 'foo=1',
      database => 'test',
      table    => 'foo',
   ),
   'SELECT `a`, `b`, `c`, COUNT(*) AS __maatkit_count FROM `test`.`foo` '
      . 'WHERE foo=1 GROUP BY `a`, `b`, `c` ORDER BY `a`, `b`, `c`',
   'Got SQL OK',
);

# Changed from undef to 0 due to r4802.
is( $t->done, 0, 'Not done yet' );

my $d = new RowDiff( dbh => 1 );
$d->compare_sets(
   left_sth => new MockSth(
      { a => 1, b => 2, c => 3, __maatkit_count => 4 },
      { a => 2, b => 2, c => 3, __maatkit_count => 4 },
      { a => 3, b => 2, c => 3, __maatkit_count => 2 },
      # { a => 4, b => 2, c => 3, __maatkit_count => 2 },
   ),
   right_sth => new MockSth(
      { a => 1, b => 2, c => 3, __maatkit_count => 3 },
      { a => 2, b => 2, c => 3, __maatkit_count => 6 },
      # { a => 3, b => 2, c => 3, __maatkit_count => 2 },
      { a => 4, b => 2, c => 3, __maatkit_count => 1 },
   ),
   syncer     => $t,
   tbl_struct => $tbl_struct,
);

is_deeply(
   \@rows,
   [
   "INSERT INTO `test`.`foo`(`a`, `b`, `c`) VALUES ('1', '2', '3')",
   "DELETE FROM `test`.`foo` WHERE `a`='2' AND `b`='2' AND `c`='3' LIMIT 1",
   "DELETE FROM `test`.`foo` WHERE `a`='2' AND `b`='2' AND `c`='3' LIMIT 1",
   "INSERT INTO `test`.`foo`(`a`, `b`, `c`) VALUES ('3', '2', '3')",
   "INSERT INTO `test`.`foo`(`a`, `b`, `c`) VALUES ('3', '2', '3')",
   "DELETE FROM `test`.`foo` WHERE `a`='4' AND `b`='2' AND `c`='3' LIMIT 1",
   ],
   'rows from handler',
) or diag(Dumper(\@rows));

# #############################################################################
# Done
# #############################################################################
done_testing;
exit;
