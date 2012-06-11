#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 26;

use TableParser;
use TableNibbler;
use Quoter;
use PerconaTest;

my $q  = new Quoter();
my $tp = new TableParser(Quoter => $q);
my $n  = new TableNibbler(
   TableParser => $tp,
   Quoter      => $q,
);

my $t;

$t = $tp->parse( load_file('t/lib/samples/sakila.film.sql') );

is_deeply(
   $n->generate_asc_stmt (
      tbl_struct => $t,
      cols       => $t->{cols},
      index      => 'PRIMARY',
   ),
   {
      cols  => [qw(film_id title description release_year language_id
                  original_language_id rental_duration rental_rate
                  length replacement_cost rating special_features
                  last_update)],
      index => 'PRIMARY',
      where => '((`film_id` >= ?))',
      slice => [0],
      scols => [qw(film_id)],
      boundaries => {
         '>=' => '((`film_id` >= ?))',
         '>'  => '((`film_id` > ?))',
         '<=' => '((`film_id` <= ?))',
         '<'  => '((`film_id` < ?))',
      },
   },
   'asc stmt on sakila.film',
);

is_deeply(
   $n->generate_del_stmt (
      tbl_struct => $t,
   ),
   {
      cols  => [qw(film_id)],
      index => 'PRIMARY',
      where => '(`film_id` = ?)',
      slice => [0],
      scols => [qw(film_id)],
   },
   'del stmt on sakila.film',
);

is_deeply(
   $n->generate_asc_stmt (
      tbl_struct => $t,
      index      => 'PRIMARY',
   ),
   {
      cols  => [qw(film_id title description release_year language_id
                  original_language_id rental_duration rental_rate
                  length replacement_cost rating special_features
                  last_update)],
      index => 'PRIMARY',
      where => '((`film_id` >= ?))',
      slice => [0],
      scols => [qw(film_id)],
      boundaries => {
         '>=' => '((`film_id` >= ?))',
         '>'  => '((`film_id` > ?))',
         '<=' => '((`film_id` <= ?))',
         '<'  => '((`film_id` < ?))',
      },
   },
   'defaults to all columns',
);

throws_ok(
   sub {
      $n->generate_asc_stmt (
         tbl_struct => $t,
         cols   => $t->{cols},
         index  => 'title',
      )
   },
   qr/Index 'title' does not exist in table/,
   'Error on nonexistent index',
);

is_deeply(
   $n->generate_asc_stmt (
      tbl_struct => $t,
      cols   => $t->{cols},
      index  => 'idx_title',
   ),
   {
      cols  => [qw(film_id title description release_year language_id
                  original_language_id rental_duration rental_rate
                  length replacement_cost rating special_features
                  last_update)],
      index => 'idx_title',
      where => '((`title` >= ?))',
      slice => [1],
      scols => [qw(title)],
      boundaries => {
         '>=' => '((`title` >= ?))',
         '>'  => '((`title` > ?))',
         '<=' => '((`title` <= ?))',
         '<'  => '((`title` < ?))',
      },
   },
   'asc stmt on sakila.film with different index',
);

is_deeply(
   $n->generate_del_stmt (
      tbl_struct => $t,
      index  => 'idx_title',
      cols   => [qw(film_id)],
   ),
   {
      cols  => [qw(film_id title)],
      index => 'idx_title',
      where => '(`title` = ?)',
      slice => [1],
      scols => [qw(title)],
   },
   'del stmt on sakila.film with different index and extra column',
);

# TableParser::find_best_index() is case-insensitive, returning the
# correct case even if the wrong case is given.  But generate_asc_stmt()
# no longer calls find_best_index() so this test is a moot point.
is_deeply(
   $n->generate_asc_stmt (
      tbl_struct => $t,
      cols   => $t->{cols},
      index  => 'idx_title',
   ),
   {
      cols  => [qw(film_id title description release_year language_id
                  original_language_id rental_duration rental_rate
                  length replacement_cost rating special_features
                  last_update)],
      index => 'idx_title',
      where => '((`title` >= ?))',
      slice => [1],
      scols => [qw(title)],
      boundaries => {
         '>=' => '((`title` >= ?))',
         '>'  => '((`title` > ?))',
         '<=' => '((`title` <= ?))',
         '<'  => '((`title` < ?))',
      },
   },
   'Index returned in correct lettercase',
);

is_deeply(
   $n->generate_asc_stmt (
      tbl_struct => $t,
      cols   => [qw(title)],
      index  => 'PRIMARY',
   ),
   {
      cols  => [qw(title film_id)],
      index => 'PRIMARY',
      where => '((`film_id` >= ?))',
      slice => [1],
      scols => [qw(film_id)],
      boundaries => {
         '>=' => '((`film_id` >= ?))',
         '>'  => '((`film_id` > ?))',
         '<=' => '((`film_id` <= ?))',
         '<'  => '((`film_id` < ?))',
      },
   },
   'Required columns added to SELECT list',
);

# ##########################################################################
# Switch to the rental table
# ##########################################################################
$t = $tp->parse( load_file('t/lib/samples/sakila.rental.sql') );

is_deeply(
   $n->generate_asc_stmt(
      tbl_struct => $t,
      cols   => $t->{cols},
      index  => 'rental_date',
   ),
   {
      cols  => [qw(rental_id rental_date inventory_id customer_id
                  return_date staff_id last_update)],
      index => 'rental_date',
      where => '((`rental_date` > ?) OR (`rental_date` = ? AND `inventory_id` > ?)'
         . ' OR (`rental_date` = ? AND `inventory_id` = ? AND `customer_id` >= ?))',
      slice => [1, 1, 2, 1, 2, 3],
      scols => [qw(rental_date rental_date inventory_id rental_date inventory_id customer_id)],
      boundaries => {
         '>=' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '`inventory_id` > ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` >= ?))',
         '>' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '`inventory_id` > ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` > ?))',
         '<=' => '((`rental_date` < ?) OR (`rental_date` = ? AND '
            . '`inventory_id` < ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` <= ?))',
         '<' => '((`rental_date` < ?) OR (`rental_date` = ? AND '
            . '`inventory_id` < ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` < ?))',
      },
   },
   'Alternate index on sakila.rental',
);

is_deeply(
   $n->generate_del_stmt (
      tbl_struct => $t,
      index  => 'rental_date',
   ),
   {
      cols  => [qw(rental_date inventory_id customer_id)],
      index => 'rental_date',
      where => '(`rental_date` = ? AND `inventory_id` = ? AND `customer_id` = ?)',
      slice => [0, 1, 2],
      scols => [qw(rental_date inventory_id customer_id)],
   },
   'Alternate index on sakila.rental delete statement',
);

# Check that I can select from one table and insert into another OK
my $f = $tp->parse( load_file('t/lib/samples/sakila.film.sql') );
is_deeply(
   $n->generate_ins_stmt(
      ins_tbl  => $f,
      sel_cols => $t->{cols},
   ),
   {
      cols  => [qw(last_update)],
      slice => [6],
   },
   'Generated an INSERT statement from film into rental',
);

my $sel_tbl = $tp->parse( load_file('t/lib/samples/issue_131_sel.sql') );
my $ins_tbl = $tp->parse( load_file('t/lib/samples/issue_131_ins.sql') );  
is_deeply(
   $n->generate_ins_stmt(
      ins_tbl  => $ins_tbl,
      sel_cols => $sel_tbl->{cols},
   ),
   {
      cols  => [qw(id name)],
      slice => [0, 2],
   },
   'INSERT stmt with different col order and a missing ins col'
);

is_deeply(
   $n->generate_asc_stmt(
      tbl_struct => $t,
      cols   => $t->{cols},
      index  => 'rental_date',
      asc_first => 1,
   ),
   {
      cols  => [qw(rental_id rental_date inventory_id customer_id
                  return_date staff_id last_update)],
      index => 'rental_date',
      where => '((`rental_date` >= ?))',
      slice => [1],
      scols => [qw(rental_date)],
      boundaries => {
         '>=' => '((`rental_date` >= ?))',
         '>'  => '((`rental_date` > ?))',
         '<=' => '((`rental_date` <= ?))',
         '<'  => '((`rental_date` < ?))',
      },
   },
   'Alternate index with asc_first on sakila.rental',
);

is_deeply(
   $n->generate_asc_stmt(
      tbl_struct   => $t,
      cols         => $t->{cols},
      index        => 'rental_date',
      n_index_cols => 2,
   ),
   {
      cols  => [qw(rental_id rental_date inventory_id customer_id
                  return_date staff_id last_update)],
      index => 'rental_date',
      where => '((`rental_date` > ?) OR (`rental_date` = ? AND `inventory_id` >= ?))',
      slice => [qw(1 1 2)],
      scols => [qw(rental_date rental_date inventory_id)],
      boundaries => {
         '<'  =>
         '((`rental_date` < ?) OR (`rental_date` = ? AND `inventory_id` < ?))',
         '<=' =>
         '((`rental_date` < ?) OR (`rental_date` = ? AND `inventory_id` <= ?))',
         '>'  =>
         '((`rental_date` > ?) OR (`rental_date` = ? AND `inventory_id` > ?))',
         '>=' =>
         '((`rental_date` > ?) OR (`rental_date` = ? AND `inventory_id` >= ?))'
      },
   },
   'Use only N left-most columns of the index',
);

is_deeply(
   $n->generate_asc_stmt(
      tbl_struct   => $t,
      cols         => $t->{cols},
      index        => 'rental_date',
      n_index_cols => 5,
   ),
   {
      cols  => [qw(rental_id rental_date inventory_id customer_id
                  return_date staff_id last_update)],
      index => 'rental_date',
      where => '((`rental_date` > ?) OR (`rental_date` = ? AND `inventory_id` > ?)'
         . ' OR (`rental_date` = ? AND `inventory_id` = ? AND `customer_id` >= ?))',
      slice => [1, 1, 2, 1, 2, 3],
      scols => [qw(rental_date rental_date inventory_id rental_date inventory_id customer_id)],
      boundaries => {
         '>=' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '`inventory_id` > ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` >= ?))',
         '>' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '`inventory_id` > ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` > ?))',
         '<=' => '((`rental_date` < ?) OR (`rental_date` = ? AND '
            . '`inventory_id` < ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` <= ?))',
         '<' => '((`rental_date` < ?) OR (`rental_date` = ? AND '
            . '`inventory_id` < ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` < ?))',
      },
   },
   "Don't crash if N > number of index columns"
);

is_deeply(
   $n->generate_asc_stmt(
      tbl_struct => $t,
      cols   => $t->{cols},
      index  => 'rental_date',
      asc_only => 1,
   ),
   {
      cols  => [qw(rental_id rental_date inventory_id customer_id
                  return_date staff_id last_update)],
      index => 'rental_date',
      where => '((`rental_date` > ?) OR (`rental_date` = ? AND `inventory_id` > ?)'
         . ' OR (`rental_date` = ? AND `inventory_id` = ? AND `customer_id` > ?))',
      slice => [1, 1, 2, 1, 2, 3],
      scols => [qw(rental_date rental_date inventory_id rental_date inventory_id customer_id)],
      boundaries => {
         '>=' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '`inventory_id` > ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` >= ?))',
         '>' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '`inventory_id` > ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` > ?))',
         '<=' => '((`rental_date` < ?) OR (`rental_date` = ? AND '
            . '`inventory_id` < ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` <= ?))',
         '<' => '((`rental_date` < ?) OR (`rental_date` = ? AND '
            . '`inventory_id` < ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` < ?))',
      },
   },
   'Alternate index on sakila.rental with strict ascending',
);

# ##########################################################################
# Switch to the rental table with customer_id nullable
# ##########################################################################
$t = $tp->parse( load_file('t/lib/samples/sakila.rental.null.sql') );

is_deeply(
   $n->generate_asc_stmt(
      tbl_struct => $t,
      cols   => $t->{cols},
      index  => 'rental_date',
   ),
   {
      cols  => [qw(rental_id rental_date inventory_id customer_id
                  return_date staff_id last_update)],
      index => 'rental_date',
      where => '((`rental_date` > ?) OR (`rental_date` = ? AND `inventory_id` > ?)'
         . ' OR (`rental_date` = ? AND `inventory_id` = ? AND '
         . '(? IS NULL OR `customer_id` >= ?)))',
      slice => [1, 1, 2, 1, 2, 3, 3],
      scols => [qw(rental_date rental_date inventory_id rental_date inventory_id customer_id customer_id)],
      boundaries => {
         '>=' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '`inventory_id` > ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND (? IS NULL OR `customer_id` >= ?)))',
         '>' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '`inventory_id` > ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND ((? IS NULL AND `customer_id` IS NOT NULL) '
            . 'OR (`customer_id` > ?))))',
         '<=' => '((`rental_date` < ?) OR (`rental_date` = ? AND '
            . '`inventory_id` < ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND (? IS NULL OR `customer_id` <= ?)))',
         '<' => '((`rental_date` < ?) OR (`rental_date` = ? AND '
            . '`inventory_id` < ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND ((? IS NOT NULL AND `customer_id` IS NULL) '
            . 'OR (`customer_id` < ?))))',
      },
   },
   'Alternate index on sakila.rental with nullable customer_id',
);

is_deeply(
   $n->generate_del_stmt (
      tbl_struct => $t,
      index  => 'rental_date',
   ),
   {
      cols  => [qw(rental_date inventory_id customer_id)],
      index => 'rental_date',
      where => '(`rental_date` = ? AND `inventory_id` = ? AND '
               . '((? IS NULL AND `customer_id` IS NULL) OR (`customer_id` = ?)))',
      slice => [0, 1, 2, 2],
      scols => [qw(rental_date inventory_id customer_id customer_id)],
   },
   'Alternate index on sakila.rental delete statement with nullable customer_id',
);

is_deeply(
   $n->generate_asc_stmt(
      tbl_struct => $t,
      cols   => $t->{cols},
      index  => 'rental_date',
      asc_only => 1,
   ),
   {
      cols  => [qw(rental_id rental_date inventory_id customer_id
                  return_date staff_id last_update)],
      index => 'rental_date',
      where => '((`rental_date` > ?) OR (`rental_date` = ? AND `inventory_id` > ?)'
         . ' OR (`rental_date` = ? AND `inventory_id` = ? AND '
         . '((? IS NULL AND `customer_id` IS NOT NULL) OR (`customer_id` > ?))))',
      slice => [1, 1, 2, 1, 2, 3, 3],
      scols => [qw(rental_date rental_date inventory_id rental_date inventory_id customer_id customer_id)],
      boundaries => {
         '>=' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '`inventory_id` > ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND (? IS NULL OR `customer_id` >= ?)))',
         '>' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '`inventory_id` > ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND ((? IS NULL AND `customer_id` IS NOT NULL) '
            . 'OR (`customer_id` > ?))))',
         '<=' => '((`rental_date` < ?) OR (`rental_date` = ? AND '
            . '`inventory_id` < ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND (? IS NULL OR `customer_id` <= ?)))',
         '<' => '((`rental_date` < ?) OR (`rental_date` = ? AND '
            . '`inventory_id` < ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND ((? IS NOT NULL AND `customer_id` IS NULL) '
            . 'OR (`customer_id` < ?))))',
      },
   },
   'Alternate index on sakila.rental with nullable customer_id and strict ascending',
);

# ##########################################################################
# Switch to the rental table with inventory_id nullable
# ##########################################################################
$t = $tp->parse( load_file('t/lib/samples/sakila.rental.null2.sql') );

is_deeply(
   $n->generate_asc_stmt(
      tbl_struct => $t,
      cols   => $t->{cols},
      index  => 'rental_date',
   ),
   {
      cols  => [qw(rental_id rental_date inventory_id customer_id
                  return_date staff_id last_update)],
      index => 'rental_date',
      where => '((`rental_date` > ?) OR '
         . '(`rental_date` = ? AND ((? IS NULL AND `inventory_id` IS NOT NULL) OR (`inventory_id` > ?)))'
         . ' OR (`rental_date` = ? AND ((? IS NULL AND `inventory_id` IS NULL) '
         . 'OR (`inventory_id` = ?)) AND `customer_id` >= ?))',
      slice => [1, 1, 2, 2, 1, 2, 2, 3],
      scols => [qw(rental_date rental_date inventory_id inventory_id
                   rental_date inventory_id inventory_id customer_id)],
      boundaries => {
         '>=' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '((? IS NULL AND `inventory_id` IS NOT NULL) OR (`inventory_id` '
            . '> ?))) OR (`rental_date` = ? AND ((? IS NULL AND `inventory_id` '
            . 'IS NULL) OR (`inventory_id` = ?)) AND `customer_id` >= ?))',
         '>' => '((`rental_date` > ?) OR (`rental_date` = ? AND ((? IS NULL '
            . 'AND `inventory_id` IS NOT NULL) OR (`inventory_id` > ?))) OR '
            . '(`rental_date` = ? AND ((? IS NULL AND `inventory_id` IS NULL) '
            . 'OR (`inventory_id` = ?)) AND `customer_id` > ?))',
         '<=' => '((`rental_date` < ?) OR (`rental_date` = ? AND ((? IS NOT '
            . 'NULL AND `inventory_id` IS NULL) OR (`inventory_id` < ?))) OR '
            . '(`rental_date` = ? AND ((? IS NULL AND `inventory_id` IS NULL) '
            . 'OR (`inventory_id` = ?)) AND `customer_id` <= ?))',
         '<' => '((`rental_date` < ?) OR (`rental_date` = ? AND ((? IS NOT '
            . 'NULL AND `inventory_id` IS NULL) OR (`inventory_id` < ?))) '
            . 'OR (`rental_date` = ? AND ((? IS NULL AND `inventory_id` IS '
            . 'NULL) OR (`inventory_id` = ?)) AND `customer_id` < ?))',
      },
   },
   'Alternate index on sakila.rental with nullable inventory_id',
);

is_deeply(
   $n->generate_asc_stmt(
      tbl_struct => $t,
      cols   => $t->{cols},
      index  => 'rental_date',
      asc_only => 1,
   ),
   {
      cols  => [qw(rental_id rental_date inventory_id customer_id
                  return_date staff_id last_update)],
      index => 'rental_date',
      where => '((`rental_date` > ?) OR '
         . '(`rental_date` = ? AND ((? IS NULL AND `inventory_id` IS NOT NULL) OR (`inventory_id` > ?)))'
         . ' OR (`rental_date` = ? AND ((? IS NULL AND `inventory_id` IS NULL) '
         . 'OR (`inventory_id` = ?)) AND `customer_id` > ?))',
      slice => [1, 1, 2, 2, 1, 2, 2, 3],
      scols => [qw(rental_date rental_date inventory_id inventory_id
                   rental_date inventory_id inventory_id customer_id)],
      boundaries => {
         '>=' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '((? IS NULL AND `inventory_id` IS NOT NULL) OR (`inventory_id` '
            . '> ?))) OR (`rental_date` = ? AND ((? IS NULL AND `inventory_id` '
            . 'IS NULL) OR (`inventory_id` = ?)) AND `customer_id` >= ?))',
         '>' => '((`rental_date` > ?) OR (`rental_date` = ? AND ((? IS NULL '
            . 'AND `inventory_id` IS NOT NULL) OR (`inventory_id` > ?))) OR '
            . '(`rental_date` = ? AND ((? IS NULL AND `inventory_id` IS NULL) '
            . 'OR (`inventory_id` = ?)) AND `customer_id` > ?))',
         '<=' => '((`rental_date` < ?) OR (`rental_date` = ? AND ((? IS NOT '
            . 'NULL AND `inventory_id` IS NULL) OR (`inventory_id` < ?))) OR '
            . '(`rental_date` = ? AND ((? IS NULL AND `inventory_id` IS NULL) '
            . 'OR (`inventory_id` = ?)) AND `customer_id` <= ?))',
         '<' => '((`rental_date` < ?) OR (`rental_date` = ? AND ((? IS NOT '
            . 'NULL AND `inventory_id` IS NULL) OR (`inventory_id` < ?))) '
            . 'OR (`rental_date` = ? AND ((? IS NULL AND `inventory_id` IS '
            . 'NULL) OR (`inventory_id` = ?)) AND `customer_id` < ?))',
      },
   },
   'Alternate index on sakila.rental with nullable inventory_id and strict ascending',
);

# ##########################################################################
# Switch to the rental table with cols in a different order.
# ##########################################################################
$t = $tp->parse( load_file('t/lib/samples/sakila.rental.remix.sql') );

is_deeply(
   $n->generate_asc_stmt(
      tbl_struct => $t,
      index  => 'rental_date',
   ),
   {
      cols  => [qw(rental_id rental_date customer_id inventory_id
                  return_date staff_id last_update)],
      index => 'rental_date',
      where => '((`rental_date` > ?) OR (`rental_date` = ? AND `inventory_id` > ?)'
         . ' OR (`rental_date` = ? AND `inventory_id` = ? AND `customer_id` >= ?))',
      slice => [1, 1, 3, 1, 3, 2],
      scols => [qw(rental_date rental_date inventory_id rental_date inventory_id customer_id)],
      boundaries => {
         '>=' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '`inventory_id` > ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` >= ?))',
         '>' => '((`rental_date` > ?) OR (`rental_date` = ? AND '
            . '`inventory_id` > ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` > ?))',
         '<=' => '((`rental_date` < ?) OR (`rental_date` = ? AND '
            . '`inventory_id` < ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` <= ?))',
         '<' => '((`rental_date` < ?) OR (`rental_date` = ? AND '
            . '`inventory_id` < ?) OR (`rental_date` = ? AND `inventory_id` '
            . '= ? AND `customer_id` < ?))',
      },
   },
   'Out-of-order index on sakila.rental',
);

# ##########################################################################
# Switch to table without any indexes
# ##########################################################################
$t = $tp->parse( load_file('t/lib/samples/t1.sql') );

# This test is no longer needed because TableSyncNibble shouldn't
# ask TableNibbler to asc an indexless table.
# throws_ok(
#    sub {
#       $n->generate_asc_stmt (
#          tbl_struct => $t,
#       )
#    },
#    qr/Cannot find an ascendable index in table/,
#    'Error when no good index',
# );

is_deeply(
   $n->generate_cmp_where(
      cols   => [qw(a b c d)],
      slice  => [0, 3],
      is_nullable => {},
      type   => '>=',
   ),
   {
      scols => [qw(a a d)],
      slice => [0, 0, 3],
      where => '((`a` > ?) OR (`a` = ? AND `d` >= ?))',
   },
   'WHERE for >=',
);

is_deeply(
   $n->generate_cmp_where(
      cols   => [qw(a b c d)],
      slice  => [0, 3],
      is_nullable => {},
      type   => '>',
   ),
   {
      scols => [qw(a a d)],
      slice => [0, 0, 3],
      where => '((`a` > ?) OR (`a` = ? AND `d` > ?))',
   },
   'WHERE for >',
);

is_deeply(
   $n->generate_cmp_where(
      cols   => [qw(a b c d)],
      slice  => [0, 3],
      is_nullable => {},
      type   => '<=',
   ),
   {
      scols => [qw(a a d)],
      slice => [0, 0, 3],
      where => '((`a` < ?) OR (`a` = ? AND `d` <= ?))',
   },
   'WHERE for <=',
);

is_deeply(
   $n->generate_cmp_where(
      cols   => [qw(a b c d)],
      slice  => [0, 3],
      is_nullable => {},
      type   => '<',
   ),
   {
      scols => [qw(a a d)],
      slice => [0, 0, 3],
      where => '((`a` < ?) OR (`a` = ? AND `d` < ?))',
   },
   'WHERE for <',
);


# #############################################################################
# Done.
# #############################################################################
exit;
