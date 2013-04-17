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

use TableParser;
use TableChunker;
use Quoter;
use DSNParser;
use Sandbox;
use PerconaTest;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

$sb->create_dbs($dbh, ['test']);

my $q  = new Quoter();
my $tp = new TableParser(Quoter => $q);
my $c  = new TableChunker(Quoter => $q, TableParser => $tp);
my $t;

$t = $tp->parse( load_file('t/lib/samples/sakila.film.sql') );
is_deeply(
   [ $c->find_chunk_columns(tbl_struct=>$t) ],
   [ 0,
     { column => 'film_id', index => 'PRIMARY' },
     { column => 'title', index => 'idx_title' },
     { column => 'language_id', index => 'idx_fk_language_id' },
     { column => 'original_language_id',
       index => 'idx_fk_original_language_id' },
   ],
   'Found chunkable columns on sakila.film',
);

is_deeply(
   [ $c->find_chunk_columns(tbl_struct=>$t, exact => 1) ],
   [ 1, { column => 'film_id', index => 'PRIMARY' } ],
   'Found exact chunkable columns on sakila.film',
);

# This test was removed because possible_keys was only used (vaguely)
# by mk-table-sync/TableSync* but this functionality is now handled
# in TableSync*::can_sync() with the optional args col and index.
# In other words: it's someone else's job to get/check the preferred index.
#is_deeply(
#   [ $c->find_chunk_columns($t, { possible_keys => [qw(idx_fk_language_id)] }) ],
#   [ 0,
#     [
#        { column => 'language_id', index => 'idx_fk_language_id' },
#        { column => 'original_language_id',
#             index => 'idx_fk_original_language_id' },
#        { column => 'film_id', index => 'PRIMARY' },
#     ]
#   ],
#   'Found preferred chunkable columns on sakila.film',
#);

$t = $tp->parse( load_file('t/lib/samples/pk_not_first.sql') );
is_deeply(
   [ $c->find_chunk_columns(tbl_struct=>$t) ],
   [ 0,
     { column => 'film_id', index => 'PRIMARY' },
     { column => 'title', index => 'idx_title' },
     { column => 'language_id', index => 'idx_fk_language_id' },
     { column => 'original_language_id',
        index => 'idx_fk_original_language_id' },
   ],
   'PK column is first',
);

is(
   $c->inject_chunks(
      query     => 'SELECT /*PROGRESS_COMMENT*//*CHUNK_NUM*/ FOO FROM 1/*WHERE*/',
      database  => 'sakila',
      table     => 'film',
      chunks    => [ '1=1', 'a=b' ],
      chunk_num => 1,
      where     => ['FOO=BAR'],
   ),
   'SELECT /*sakila.film:2/2*/ 1 AS chunk_num, FOO FROM 1 WHERE (a=b) AND ((FOO=BAR))',
   'Replaces chunk info into query',
);

is(
   $c->inject_chunks(
      query     => 'SELECT /*PROGRESS_COMMENT*//*CHUNK_NUM*/ FOO FROM 1/*WHERE*/',
      database  => 'sakila',
      table     => 'film',
      chunks    => [ '1=1', 'a=b' ],
      chunk_num => 1,
      where     => ['FOO=BAR', undef],
   ),
   'SELECT /*sakila.film:2/2*/ 1 AS chunk_num, FOO FROM 1 WHERE (a=b) AND ((FOO=BAR))',
   'Inject WHERE clause with undef item',
);

is(
   $c->inject_chunks(
      query     => 'SELECT /*PROGRESS_COMMENT*//*CHUNK_NUM*/ FOO FROM 1/*WHERE*/',
      database  => 'sakila',
      table     => 'film',
      chunks    => [ '1=1', 'a=b' ],
      chunk_num => 1,
      where     => ['FOO=BAR', 'BAZ=BAT'],
   ),
   'SELECT /*sakila.film:2/2*/ 1 AS chunk_num, FOO FROM 1 WHERE (a=b) '
      . 'AND ((FOO=BAR) AND (BAZ=BAT))',
   'Inject WHERE with defined item',
);

# #############################################################################
# Sandbox tests.
# #############################################################################
SKIP: {
   skip 'Sandbox master does not have the sakila database', 21
      unless @{$dbh->selectcol_arrayref("SHOW DATABASES LIKE 'sakila'")};

   my @chunks;

   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'film_id',
      min           => 0,
      max           => 99,
      rows_in_range => 100,
      chunk_size    => 30,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'film',
   );
   is_deeply(
      \@chunks,
      [
         "`film_id` < '30'",
         "`film_id` >= '30' AND `film_id` < '60'",
         "`film_id` >= '60' AND `film_id` < '90'",
         "`film_id` >= '90'",
      ],
      'Got the right chunks from dividing 100 rows into 30-row chunks',
   );

   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'film_id',
      min           => 0,
      max           => 99,
      rows_in_range => 100,
      chunk_size    => 300,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'film',
   );
   is_deeply(
      \@chunks,
      [
         '1=1',
      ],
      'Got the right chunks from dividing 100 rows into 300-row chunks',
   );

   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'film_id',
      min           => 0,
      max           => 0,
      rows_in_range => 100,
      chunk_size    => 300,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'film',
   );
   is_deeply(
      \@chunks,
      [
         '1=1',
      ],
      'No rows, so one chunk',
   );

   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'original_language_id',
      min           => 0,
      max           => 99,
      rows_in_range => 100,
      chunk_size    => 50,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'film',
   );
   is_deeply(
      \@chunks,
      [
         "`original_language_id` < '50'",
         "`original_language_id` >= '50'",
         "`original_language_id` IS NULL",
      ],
      'Nullable column adds IS NULL chunk',
   );

   $t = $tp->parse( load_file('t/lib/samples/daycol.sql') );

   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'a',
      min           => '2001-01-01',
      max           => '2002-01-01',
      rows_in_range => 365,
      chunk_size    => 90,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'checksum_test_5',
   );
   is_deeply(
      \@chunks,
      [
         "`a` < '2001-04-01'",
         "`a` >= '2001-04-01' AND `a` < '2001-06-30'",
         "`a` >= '2001-06-30' AND `a` < '2001-09-28'",
         "`a` >= '2001-09-28' AND `a` < '2001-12-27'",
         "`a` >= '2001-12-27'",
      ],
      'Date column chunks OK',
   );

   $t = $tp->parse( load_file('t/lib/samples/date.sql') );
   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'a',
      min           => '2000-01-01',
      max           => '2005-11-26',
      rows_in_range => 3,
      chunk_size    => 1,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'checksum_test_5',
   );
   is_deeply(
      \@chunks,
      [
         "`a` < '2001-12-20'",
         "`a` >= '2001-12-20' AND `a` < '2003-12-09'",
         "`a` >= '2003-12-09'",
      ],
      'Date column chunks OK',
   );

   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'a',
      min           => '0000-00-00',
      max           => '2005-11-26',
      rows_in_range => 3,
      chunk_size    => 1,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'checksum_test_5',
   );
   is_deeply(
      \@chunks,
      [
         "`a` < '0668-08-20'",
         "`a` >= '0668-08-20' AND `a` < '1337-04-09'",
         "`a` >= '1337-04-09'",
      ],
      'Date column where min date is 0000-00-00',
   );

   $t = $tp->parse( load_file('t/lib/samples/datetime.sql') );
   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'a',
      min           => '1922-01-14 05:18:23',
      max           => '2005-11-26 00:59:19',
      rows_in_range => 3,
      chunk_size    => 1,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'checksum_test_5',
   );
   is_deeply(
      \@chunks,
      [
         "`a` < '1949-12-28 19:52:02'",
         "`a` >= '1949-12-28 19:52:02' AND `a` < '1977-12-12 10:25:41'",
         "`a` >= '1977-12-12 10:25:41'",
      ],
      'Datetime column chunks OK',
   );

   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'a',
      min           => '0000-00-00 00:00:00',
      max           => '2005-11-26 00:59:19',
      rows_in_range => 3,
      chunk_size    => 1,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'checksum_test_5',
   );
   is_deeply(
      \@chunks,
      [
         "`a` < '0668-08-19 16:19:47'",
         "`a` >= '0668-08-19 16:19:47' AND `a` < '1337-04-08 08:39:34'",
         "`a` >= '1337-04-08 08:39:34'",
      ],
      'Datetime where min is 0000-00-00 00:00:00',
   );

   $t = $tp->parse( load_file('t/lib/samples/timecol.sql') );
   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'a',
      min           => '00:59:19',
      max           => '09:03:15',
      rows_in_range => 3,
      chunk_size    => 1,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'checksum_test_7',
   );
   is_deeply(
      \@chunks,
      [
         "`a` < '03:40:38'",
         "`a` >= '03:40:38' AND `a` < '06:21:57'",
         "`a` >= '06:21:57'",
      ],
      'Time column chunks OK',
   );

   $t = $tp->parse( load_file('t/lib/samples/doublecol.sql') );
   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'a',
      min           => '1',
      max           => '99.999',
      rows_in_range => 3,
      chunk_size    => 1,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'checksum_test_8',
   );
   is_deeply(
      \@chunks,
      [
         "`a` < '33.99966'",
         "`a` >= '33.99966' AND `a` < '66.99933'",
         "`a` >= '66.99933'",
      ],
      'Double column chunks OK',
   );

   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'a',
      min           => '1',
      max           => '2',
      rows_in_range => 5,
      chunk_size    => 3,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'checksum_test_5',
   );
   is_deeply(
      \@chunks,
      [
         "`a` < '1.6'",
         "`a` >= '1.6'",
      ],
      'Double column chunks OK with smaller-than-int values',
   );

   eval {
      @chunks = $c->calculate_chunks(
         tbl_struct    => $t,
         chunk_col     => 'a',
         min           => '1',
         max           => '2',
         rows_in_range => 50000000,
         chunk_size    => 3,
         dbh           => $dbh,
         db            => 'sakila',
         tbl           => 'checksum_test_5',
      );
   };
   is(
      $EVAL_ERROR,
      "Chunk size is too small: 1.00000 !> 1\n",
      'Throws OK when too many chunks',
   );

   $t = $tp->parse( load_file('t/lib/samples/floatcol.sql') );
   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'a',
      min           => '1',
      max           => '99.999',
      rows_in_range => 3,
      chunk_size    => 1,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'checksum_test_5',
   );
   is_deeply(
      \@chunks,
      [
         "`a` < '33.99966'",
         "`a` >= '33.99966' AND `a` < '66.99933'",
         "`a` >= '66.99933'",
      ],
      'Float column chunks OK',
   );

   $t = $tp->parse( load_file('t/lib/samples/decimalcol.sql') );
   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'a',
      min           => '1',
      max           => '99.999',
      rows_in_range => 3,
      chunk_size    => 1,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'checksum_test_5',
   );
   is_deeply(
      \@chunks,
      [
         "`a` < '33.99966'",
         "`a` >= '33.99966' AND `a` < '66.99933'",
         "`a` >= '66.99933'",
      ],
      'Decimal column chunks OK',
   );

   throws_ok(
      sub { $c->get_range_statistics(
            dbh        => $dbh,
            db         => 'sakila',
            tbl        => 'film',
            chunk_col  => 'film_id',
            tbl_struct => {
               type_for   => { film_id => 'int' },
               is_numeric => { film_id => 1     },
            },
            where      => 'film_id>'
         )
      },
      qr/WHERE \(film_id>\)/,
      'Shows full SQL on error',
   );

   throws_ok(
      sub { $c->size_to_rows(
            dbh        => $dbh,
            db         => 'sakila',
            tbl        => 'film',
            chunk_size => 'foo'
         )
      },
      qr/Invalid chunk size/,
      'Rejects chunk size',
   );

   is_deeply(
      [ $c->size_to_rows(
         dbh        => $dbh,
         db         => 'sakila',
         tbl        => 'film',
         chunk_size => '5'
      ) ],
      [5, undef],
      'Numeric size'
   );
   my ($size) = $c->size_to_rows(
      dbh        => $dbh,
      db         => 'sakila',
      tbl        => 'film',
      chunk_size => '5k'
   );
   ok($size >= 20 && $size <= 30, 'Convert bytes to rows');

   my $avg;
   ($size, $avg) = $c->size_to_rows(
      dbh        => $dbh,
      db         => 'sakila',
      tbl        => 'film',
      chunk_size => '5k'
   );
   # This will fail if we try to set a specific range, because Rows and
   # Avg_row_length can vary slightly-to-greatly for InnoDB tables.
   like(
      $avg, qr/^\d+$/,
      "size_to_rows() returns avg row len in list context ($avg)"
   );

   ($size, $avg) = $c->size_to_rows(
      dbh            => $dbh,
      db             => 'sakila',
      tbl            => 'film',
      chunk_size     => 5,
      avg_row_length => 1,
   );
   # diag('size ', $size || 'undef', 'avg ', $avg || 'undef');
   ok(
      $size == 5 && ($avg >= 150 && $avg <= 280),
      'size_to_rows() gets avg row length if asked'
   );


   # #########################################################################
   # Issue 1084: Don't try to chunk small tables
   # #########################################################################
   $t = $tp->parse( $tp->get_create_table($dbh, 'sakila', 'country') );
   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'country_id',
      min           => '1',
      max           => '109',
      rows_in_range => 109,
      chunk_size    => 110,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'country',
   );
   is_deeply(
      \@chunks,
      ["1=1"],
      "Doesn't chunk if chunk size > total rows"
   );
};

# #############################################################################
# Issue 47: TableChunker::range_num broken for very large bigint
# #############################################################################
$sb->load_file('master', 't/lib/samples/issue_47.sql');
$t = $tp->parse( $tp->get_create_table($dbh, 'test', 'issue_47') );
my %params = $c->get_range_statistics(
   dbh        => $dbh,
   db         => 'test',
   tbl        => 'issue_47',
   chunk_col  => 'userid',
   tbl_struct => {
      type_for   => { userid => 'int' },
      is_numeric => { userid => 1     },
   },
);
my @chunks;
eval {
   @chunks = $c->calculate_chunks(
      dbh        => $dbh,
      tbl_struct => $t,
      chunk_col  => 'userid',
      chunk_size => '4',
      %params,
   );
};
unlike($EVAL_ERROR, qr/Chunk size is too small/, 'Does not die chunking unsigned bitint (issue 47)');

# #############################################################################
# Issue 8: Add --force-index parameter to mk-table-checksum and mk-table-sync
# #############################################################################
is(
   $c->inject_chunks(
      query       => 'SELECT /*CHUNK_NUM*/ FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/',
      database    => 'test',
      table       => 'issue_8',
      chunks      => [ '1=1', 'a=b' ],
      chunk_num   => 1,
      where       => [],
      index_hint  => 'USE INDEX (`idx_a`)',
   ),
   'SELECT  1 AS chunk_num, FROM `test`.`issue_8` USE INDEX (`idx_a`) WHERE (a=b)',
   'Adds USE INDEX (issue 8)'
);

$sb->load_file('master', 't/lib/samples/issue_8.sql');
$t = $tp->parse( $tp->get_create_table($dbh, 'test', 'issue_8') );
my @candidates = $c->find_chunk_columns(tbl_struct=>$t);
is_deeply(
   \@candidates,
   [
      0,
      { column => 'id',    index => 'PRIMARY'  },
      { column => 'foo',   index => 'uidx_foo' },
   ],
   'find_chunk_columns() returns col and idx candidates'
);

# #############################################################################
# Issue 941: mk-table-checksum chunking should treat zero dates similar to NULL
# #############################################################################
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# These tables have rows like: 0, 100, 101, 102, etc.  Without the
# zero-row option, the result is like:
#   range stats:
#     min           => '0',
#     max           => '107',
#     rows_in_range => '9'
#   chunks:
#     '`i` < 24',
#     '`i` >= 24 AND `i` < 48',
#     '`i` >= 48 AND `i` < 72',
#     '`i` >= 72 AND `i` < 96',
#     '`i` >= 96'
# Problem is that the last chunk does all the work.  If the zero row
# is ignored then the chunks are much better and the first chunk will
# cover the zero row.

$sb->load_file('master', 't/lib/samples/issue_941.sql');

sub test_zero_row {
   my ( $tbl, $range, $chunks, $zero_chunk ) = @_;
   $zero_chunk = 1 unless defined $zero_chunk;
   $t = $tp->parse( $tp->get_create_table($dbh, 'issue_941', $tbl) );
   %params = $c->get_range_statistics(
      dbh        => $dbh,
      db         => 'issue_941',
      tbl        => $tbl,
      chunk_col  => $tbl,
      tbl_struct => $t,
      zero_chunk => $zero_chunk,
   );
   is_deeply(
      \%params,
      $range,
      "$tbl range without zero row"
   ) or print STDERR "Got ", Dumper(\%params);

   @chunks = $c->calculate_chunks(
      dbh        => $dbh,
      db         => 'issue_941',
      tbl        => $tbl,
      tbl_struct => $t,
      chunk_col  => $tbl,
      chunk_size => '2',
      zero_chunk => $zero_chunk,
      %params,
   );
   is_deeply(
      \@chunks,
      $chunks,
      "$tbl chunks without zero row"
   ) or print STDERR "Got ", Dumper(\@chunks);

   return;
}

# This can zero chunk because the min, 0, is >= 0.
# The effective min becomes 100.
test_zero_row(
   'i',
   { min=>0, max=>107, rows_in_range=>9 },
   [
      "`i` = 0",
      "`i` > 0 AND `i` < '102'",
      "`i` >= '102' AND `i` < '104'",
      "`i` >= '104' AND `i` < '106'",
      "`i` >= '106'",
   ],
);

# This cannot zero chunk because the min is < 0.
test_zero_row(
   'i_neg',
   { min=>-10, max=>-2, rows_in_range=>8 },
   [
      "`i_neg` < '-8'",
      "`i_neg` >= '-8' AND `i_neg` < '-6'",
      "`i_neg` >= '-6' AND `i_neg` < '-4'",
      "`i_neg` >= '-4'"
   ],
);

# This cannot zero chunk because the min is < 0.
test_zero_row(
   'i_neg_pos',
   { min=>-10, max=>4, rows_in_range=>14 },
   [
      "`i_neg_pos` < '-8'",
      "`i_neg_pos` >= '-8' AND `i_neg_pos` < '-6'",
      "`i_neg_pos` >= '-6' AND `i_neg_pos` < '-4'",
      "`i_neg_pos` >= '-4' AND `i_neg_pos` < '-2'",
      "`i_neg_pos` >= '-2' AND `i_neg_pos` < '0'",
      "`i_neg_pos` >= '0' AND `i_neg_pos` < '2'",
      "`i_neg_pos` >= '2'",
   ],
);

# There's no zero values in this table, but it can still
# zero chunk because the min is >= 0.
test_zero_row(
   'i_null',
   { min=>100, max=>107, rows_in_range=>9 },
   [
      "`i_null` = 0",
      "`i_null` > 0 AND `i_null` < '102'",
      "`i_null` >= '102' AND `i_null` < '104'",
      "`i_null` >= '104' AND `i_null` < '106'",
      "`i_null` >= '106'",
      "`i_null` IS NULL",
   ],
);

# Table d has a zero row, 0000-00-00, which is not a valid value
# for min but can be selected by the zero chunk.
test_zero_row(
   'd',
   {
      min => '2010-03-01',
      max => '2010-03-05',
      rows_in_range => '6'
   },
   [
      "`d` = 0",
      "`d` > 0 AND `d` < '2010-03-03'",
      "`d` >= '2010-03-03'",
   ],
);

# Same as above: one zero row which we can select with the zero chunk.
test_zero_row(
   'dt',
   {
      min => '2010-03-01 02:01:00',
      max => '2010-03-05 00:30:00',
      rows_in_range => '6',
   },
   [
      "`dt` = 0",
      "`dt` > 0 AND `dt` < '2010-03-02 09:30:40'",
      "`dt` >= '2010-03-02 09:30:40' AND `dt` < '2010-03-03 17:00:20'",
      "`dt` >= '2010-03-03 17:00:20'",
   ],
);

# #############################################################################
# Issue 602: mk-table-checksum issue with invalid dates
# #############################################################################
$sb->load_file('master', 't/pt-table-checksum/samples/issue_602.sql');
$t = $tp->parse( $tp->get_create_table($dbh, 'issue_602', 't') );
%params = $c->get_range_statistics(
   dbh        => $dbh,
   db         => 'issue_602',
   tbl        => 't',
   chunk_col  => 'b',
   tbl_struct => {
      type_for   => { b => 'datetime' },
      is_numeric => { b => 0          },
   },
);

is_deeply(
   \%params,
   {
      max => '2010-05-09 00:00:00',
      min => '2010-04-30 00:00:00',
      rows_in_range => '11',
   },
   "Ignores invalid min val, gets next valid min val"
);

throws_ok(
   sub {
      @chunks = $c->calculate_chunks(
         dbh        => $dbh,
         db         => 'issue_602',
         tbl        => 't',
         tbl_struct => $t,
         chunk_col  => 'b',
         chunk_size => '5',
         %params,
      )
   },
   qr//,
   "No error with invalid min datetime (issue 602)"
);

# Like the test above but t2 has nothing but invalid rows.
$t = $tp->parse( $tp->get_create_table($dbh, 'issue_602', 't2') );
throws_ok(
   sub {
      $c->get_range_statistics(
         dbh        => $dbh,
         db         => 'issue_602',
         tbl        => 't2',
         chunk_col  => 'b',
         tbl_struct => {
            type_for   => { b => 'datetime' },
            is_numeric => { b => 0          },
         },
      );
   },
   qr/Error finding a valid minimum value/,
   "Dies if valid min value cannot be found"
);

# Try again with more tries: 6 instead of default 5.  Should
# find a row this time.
%params = $c->get_range_statistics(
   dbh        => $dbh,
   db         => 'issue_602',
   tbl        => 't2',
   chunk_col  => 'b',
   tbl_struct => {
      type_for   => { b => 'datetime' },
      is_numeric => { b => 0          },
   },
   tries     => 6,
);

is_deeply(
   \%params,
   {
      max => '2010-01-08 00:00:08',
      min => '2010-01-07 00:00:07',
      rows_in_range => 8,
   },
   "Gets valid min with enough tries"
);


# #############################################################################
# Test issue 941 + issue 602
# #############################################################################

$dbh->do("insert into issue_602.t values ('12', '0000-00-00 00:00:00')");
# Now we have:
# |   12 | 0000-00-00 00:00:00 | 
# |   11 | 2010-00-09 00:00:00 | 
# |   10 | 2010-04-30 00:00:00 | 
# So min is a zero row.  If we don't want zero row, next min will be an
# invalid row, and we don't want that.  So we should get row "10" as min.

%params = $c->get_range_statistics(
   dbh        => $dbh,
   db         => 'issue_602',
   tbl        => 't',
   chunk_col  => 'b',
   tbl_struct => {
      type_for   => { b => 'datetime' },
      is_numeric => { b => 0          },
   },
);

is_deeply(
   \%params,
   {
      min => '2010-04-30 00:00:00',
      max => '2010-05-09 00:00:00',
      rows_in_range => 12,
   },
   "Gets valid min after zero row"
);

# #############################################################################
# Test _validate_temporal_value() because it's magical.
# #############################################################################
my @invalid_t = (
   '00:00:60',
   '00:60:00',
   '0000-00-00',
   '2009-00-00',
   '2009-13-00',
   '0000-00-00 00:00:00',
   '1000-00-00 00:00:00',
   '2009-00-00 00:00:00',
   '2009-13-00 00:00:00',
   '2009-05-26 00:00:60',
   '2009-05-26 00:60:00',
   '2009-05-26 24:00:00',
);
foreach my $t ( @invalid_t ) {
   my $res = TableChunker::_validate_temporal_value($dbh, $t);
   is(
      $res,
      undef,
      "$t is invalid"
   );
}

my @valid_t = (
   '00:00:01',
   '1000-01-01',
   '2009-01-01',
   '1000-01-01 00:00:00',
   '2009-01-01 00:00:00',
   '2010-05-26 17:48:30',
);
foreach my $t ( @valid_t ) {
   my $res = TableChunker::_validate_temporal_value($dbh, $t);
   ok(
      defined $res,
      "$t is valid"
   );
}

# #############################################################################
# Test get_first_chunkable_column().
# #############################################################################
$t = $tp->parse( load_file('t/lib/samples/sakila.film.sql') );

is_deeply(
   [ $c->get_first_chunkable_column(tbl_struct=>$t) ],
   [ 'film_id', 'PRIMARY' ],
   "get_first_chunkable_column(), default column and index"
);

is_deeply(
   [ $c->get_first_chunkable_column(
      tbl_struct   => $t,
      chunk_column => 'language_id',
   ) ],
   [ 'language_id', 'idx_fk_language_id' ],
   "get_first_chunkable_column(), preferred column"
);

is_deeply(
   [ $c->get_first_chunkable_column(
      tbl_struct  => $t,
      chunk_index => 'idx_fk_original_language_id',
   ) ],
   [ 'original_language_id', 'idx_fk_original_language_id' ],
   "get_first_chunkable_column(), preferred index"
);

is_deeply(
   [ $c->get_first_chunkable_column(
      tbl_struct   => $t,
      chunk_column => 'language_id',
      chunk_index  => 'idx_fk_language_id',
   ) ],
   [ 'language_id', 'idx_fk_language_id' ],
   "get_first_chunkable_column(), preferred column and index"
);

is_deeply(
   [ $c->get_first_chunkable_column(
      tbl_struct   => $t,
      chunk_column => 'film_id',
      chunk_index  => 'idx_fk_language_id',
   ) ],
   [ 'film_id', 'PRIMARY' ],
   "get_first_chunkable_column(), bad preferred column and index"
);

$sb->load_file('master', "t/lib/samples/t1.sql", 'test');
$t = $tp->parse( load_file('t/lib/samples/t1.sql') );

is_deeply(
   [ $c->get_first_chunkable_column(tbl_struct=>$t) ],
   [undef, undef],
   "get_first_chunkable_column(), no chunkable columns"
);

# char chunking ###############################################################
$sb->load_file('master', "t/lib/samples/char-chunking/ascii.sql", 'test');
$t = $tp->parse( $tp->get_create_table($dbh, 'test', 'ascii') );

is_deeply(
   [ $c->find_chunk_columns(tbl_struct=>$t) ],
   [ 0,
     { column => 'i', index => 'PRIMARY' },
     { column => 'c', index => 'c'       },
   ],
   "Finds character column as a chunkable column"
);

is_deeply(
   [ $c->get_first_chunkable_column(tbl_struct=>$t) ],
   ['i', 'PRIMARY'],
   "get_first_chunkable_column(), prefers PK over char col"
);
is_deeply(
   [ $c->get_first_chunkable_column(tbl_struct=>$t, chunk_column=>'c') ],
   ['c', 'c'],
   "get_first_chunkable_column(), char col as preferred chunk col"
);
is_deeply(
   [ $c->get_first_chunkable_column(tbl_struct=>$t, chunk_index=>'c') ],
   ['c', 'c'],
   "get_first_chunkable_column(), char col as preferred chunk index"
);

%params = $c->get_range_statistics(
   dbh        => $dbh,
   db         => 'test',
   tbl        => 'ascii',
   chunk_col  => 'c',
   tbl_struct => $t,
);
is_deeply(
   \%params,
   {
      min           => '',
      max           => 'ZESUS!!!',
      rows_in_range => '142',
   },
   "Range stats on character column"
);

# #############################################################################
# Issue 1082: mk-table-checksum dies on single-row zero-pk table
# #############################################################################
sub chunk_it {
   my ( %args ) = @_;
   my %params = $c->get_range_statistics(
      dbh        => $dbh,
      db         => $args{db},
      tbl        => $args{tbl},
      chunk_col  => $args{chunk_col},
      tbl_struct => $args{tbl_struct},
   );
   my @chunks = $c->calculate_chunks(
      dbh        => $dbh,
      db         => $args{db},
      tbl        => $args{tbl},
      chunk_col  => $args{chunk_col},
      tbl_struct => $args{tbl_struct},
      chunk_size => $args{chunk_size} || 100,
      zero_chunk => $args{zero_chunk},
      %params,
   );
   is_deeply(
      \@chunks,
      $args{chunks},
      $args{msg},
   );
}

$dbh->do("alter table test.t1 add unique index (a)");
my (undef,$output) = $dbh->selectrow_array("show create table test.t1");
$t = $tp->parse($output);
is_deeply(
   [ $c->get_first_chunkable_column(tbl_struct=>$t) ],
   [qw(a a)],
   "test.t1 chunkable col"
);

$dbh->do('insert into test.t1 values (null)');
chunk_it(
   dbh        => $dbh,
   db         => 'test',
   tbl        => 't1',
   chunk_col  => 'a',
   tbl_struct => $t,
   zero_chunk => 1,
   chunks     => [qw(1=1)],
   msg        => 'Single NULL row'
);

$dbh->do('insert into test.t1 values (null), (null), (null)');
chunk_it(
   dbh        => $dbh,
   db         => 'test',
   tbl        => 't1',
   chunk_col  => 'a',
   tbl_struct => $t,
   zero_chunk => 1,
   chunks     => [qw(1=1)],
   msg        => 'Several NULL rows'
);

$dbh->do('truncate table test.t1');
$dbh->do('insert into test.t1 values (0)');
chunk_it(
   dbh        => $dbh,
   db         => 'test',
   tbl        => 't1',
   chunk_col  => 'a',
   tbl_struct => $t,
   zero_chunk => 1,
   chunks     => [qw(1=1)],
   msg        => 'Single zero row'
);

# #############################################################################
# Issue 568: char chunking
# #############################################################################
sub count_rows {
   my ( $db_tbl, $col, @chunks ) = @_;
   my $total_rows = 0;
   foreach my $chunk ( @chunks ) {
      my $sql    = "SELECT $col FROM $db_tbl WHERE ($chunk) ORDER BY $col";
      my $rows   = $dbh->selectall_arrayref($sql);
      my $n_rows = scalar @$rows;
      $total_rows += $n_rows;
   }
   return $total_rows;
}

SKIP: {
   skip 'Sandbox master does not have the sakila database', 1
      unless @{$dbh->selectcol_arrayref("SHOW DATABASES LIKE 'sakila'")};

   my @chunks;

   $t = $tp->parse( $tp->get_create_table($dbh, 'sakila', 'city') );
   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'city',
      min           => 'A Corua (La Corua)',
      max           => 'Ziguinchor',
      rows_in_range => 428,
      chunk_size    => 20,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'city',
   );
   is_deeply(
      \@chunks,
      [
         "`city` < 'C'",
         "`city` >= 'C' AND `city` < 'D'",
         "`city` >= 'D' AND `city` < 'E'",
         "`city` >= 'E' AND `city` < 'F'",
         "`city` >= 'F' AND `city` < 'G'",
         "`city` >= 'G' AND `city` < 'H'",
         "`city` >= 'H' AND `city` < 'I'",
         "`city` >= 'I' AND `city` < 'J'",
         "`city` >= 'J' AND `city` < 'K'",
         "`city` >= 'K' AND `city` < 'L'",
         "`city` >= 'L' AND `city` < 'M'",
         "`city` >= 'M' AND `city` < 'N'",
         "`city` >= 'N' AND `city` < 'O'",
         "`city` >= 'O' AND `city` < 'P'",
         "`city` >= 'P' AND `city` < 'Q'",
         "`city` >= 'Q' AND `city` < 'R'",
         "`city` >= 'R' AND `city` < 'S'",
         "`city` >= 'S' AND `city` < 'T'",
         "`city` >= 'T' AND `city` < 'U'",
         "`city` >= 'U' AND `city` < 'V'",
         "`city` >= 'V' AND `city` < 'W'",
         "`city` >= 'W' AND `city` < 'X'",
         "`city` >= 'X' AND `city` < 'Y'",
         "`city` >= 'Y' AND `city` < 'Z'",
         "`city` >= 'Z'",
      ],
      "Char chunk sakila.city.city"
   );

   my $n_rows = count_rows("sakila.city", "city", @chunks);
   is(
      $n_rows,
      600,
      "sakila.city.city chunks select exactly 600 rows"
   );
}

$sb->load_file('master', "t/lib/samples/char-chunking/world-city.sql", 'test');
$t = $tp->parse( $tp->get_create_table($dbh, 'test', 'world_city') );
%params = $c->get_range_statistics(
   dbh        => $dbh,
   db         => 'test',
   tbl        => 'world_city',
   chunk_col  => 'name',
   tbl_struct => $t,
   chunk_size => '500',
);
@chunks = $c->calculate_chunks(
   dbh           => $dbh,
   db            => 'test',
   tbl           => 'world_city',
   tbl_struct    => $t,
   chunk_col     => 'name',
   chunk_size    => 500,
   %params,
);
ok(
   @chunks >= 9,
   "At least 9 char chunks on test.world_city.name"
) or print STDERR Dumper(\@chunks);

SKIP: {
   skip "Behaves differently on 5.5, code is a zombie, don't care",
   1, $sandbox_version ge '5.1';
   my $n_rows = count_rows("test.world_city", "name", @chunks);
   is(
      $n_rows,
      4079,
      "test.world_city.name chunks select exactly 4,079 rows"
   );
}

# #############################################################################
# Bug #897758: TableChunker dies from an uninit value
# #############################################################################

@chunks = $c->calculate_chunks(
   dbh           => $dbh,
   db            => 'test',
   tbl           => 'world_city',
   tbl_struct    => $t,
   chunk_col     => 'name',
   chunk_size    => 500,
   %params,
   chunk_range   => undef,
);

ok( @chunks, "calculate_chunks picks a sane default for chunk_range" );

# #############################################################################
# Issue 1182: mk-table-checksum not respecting chunk size
# #############################################################################
SKIP: {
   skip 'Sandbox master does not have the sakila database', 1
      unless @{$dbh->selectcol_arrayref("SHOW DATABASES LIKE 'sakila'")};

   my @chunks;
   $t = $tp->parse( load_file('t/lib/samples/sakila.film.sql') );

   @chunks = $c->calculate_chunks(
      tbl_struct    => $t,
      chunk_col     => 'film_id',
      min           => 0,
      max           => 99,
      rows_in_range => 100,
      chunk_size    => 30,
      dbh           => $dbh,
      db            => 'sakila',
      tbl           => 'film',
      chunk_range   => 'openclosed',
   );
   is_deeply(
      \@chunks,
      [
         "`film_id` < '30'",
         "`film_id` >= '30' AND `film_id` < '60'",
         "`film_id` >= '60' AND `film_id` < '90'",
         "`film_id` >= '90' AND `film_id` <= '99'",
      ],
      'openclosed chunk range adds AND chunk_col <= max (issue 1182)'
   );
};

# ############################################################################
# Bug 821673: pt-table-checksum doesn't included --where in min max queries
# ############################################################################
$sb->load_file('master', "t/pt-table-checksum/samples/where01.sql");
$t = $tp->parse( $tp->get_create_table($dbh, 'test', 'checksum_test') );
%params = $c->get_range_statistics(
   dbh        => $dbh,
   db         => 'test',
   tbl        => 'checksum_test',
   chunk_col  => 'id',
   tbl_struct => $t,
   where      => "date = '2011-03-03'",
);
is(
   $params{min},
   11,
   'MIN int range stats with --where (bug 821673)'
);
is(
   $params{max},
   15,
   'MAX int range stats with --where (bug 821673)'
);

# char chunking
$sb->load_file('master', "t/pt-table-checksum/samples/where02.sql");
$t = $tp->parse( $tp->get_create_table($dbh, 'test', 'checksum_test') );
%params = $c->get_range_statistics(
   dbh        => $dbh,
   db         => 'test',
   tbl        => 'checksum_test',
   chunk_col  => 'id',
   tbl_struct => $t,
   where      => "date = '2011-03-03'",
);
is(
   $params{min},
   'Apple',
   'MIN char range stats with --where (bug 821673)'
);
is(
   $params{max},
   'raspberry',
   'MAX char range stats with --where (bug 821673)'
);

# It's difficult to construct a char chunk test where WHERE will matter.
#@chunks = $c->calculate_chunks(
#   dbh           => $dbh,
#   db            => 'test',
#   tbl           => 'checksum_test',
#   tbl_struct    => $t,
#   chunk_col     => 'id',
#   chunk_size    => 5,
#   where         => "date = '2011-03-03'",
#   %params,
#);

# #############################################################################
# Bug 967451: Char chunking doesn't quote column name
# #############################################################################
$sb->load_file('master', "t/lib/samples/char-chunking/ascii.sql", 'test');
$dbh->do("ALTER TABLE test.ascii CHANGE COLUMN c `key` char(64) NOT NULL");
$t = $tp->parse( $tp->get_create_table($dbh, 'test', 'ascii') );

%params = $c->get_range_statistics(
   dbh        => $dbh,
   db         => 'test',
   tbl        => 'ascii',
   chunk_col  => 'key',
   tbl_struct => $t,
);
is_deeply(
   \%params,
   {
      min           => '',
      max           => 'ZESUS!!!',
      rows_in_range => '142',
   },
   "Range stats for `key` col (bug 967451)"
);

@chunks = $c->calculate_chunks(
   dbh        => $dbh,
   db         => 'test',
   tbl        => 'ascii',
   tbl_struct => $t,
   chunk_col  => 'key',
   chunk_size => '50',
   %params,
);
is_deeply(
   \@chunks,
   [
      "`key` < '5'",
      "`key` >= '5' AND `key` < 'I'",
      "`key` >= 'I'",
   ],
   "Caclulate chunks for `key` col (bug 967451)"
);

# ############################################################################# ">
# base_count fails on n = 1000, base = 10
# https://bugs.launchpad.net/percona-toolkit/+bug/1028710
# #############################################################################
my $res = TableChunker->base_count(
   count_to => 1000,
   base     => 10,
   symbols  => ["a".."z"],
);

is(
   $res,
   "baaa",
   "base_count's floor()s account for floating point arithmetics",
);

# #############################################################################
# Bug 1034717: Divison by zero error when all columns tsart with the same char
# https://bugs.launchpad.net/percona-toolkit/+bug/1034717
# #############################################################################
$sb->load_file('master', "t/lib/samples/bug_1034717.sql", 'test');
$t = $tp->parse( $tp->get_create_table($dbh, 'bug_1034717', 'table1') );

%params = $c->get_range_statistics(
   dbh        => $dbh,
   db         => 'bug_1034717',
   tbl        => 'table1',
   chunk_col  => 'field1',
   tbl_struct => $t,
);

local $EVAL_ERROR;
eval {
   $c->calculate_chunks(
      dbh        => $dbh,
      db         => 'bug_1034717',
      tbl        => 'table1',
      tbl_struct => $t,
      chunk_col  => 'field1',
      chunk_size => '50',
      %params,
   );
};
like(
   $EVAL_ERROR,
   qr/^\QCannot chunk table `bug_1034717`.`table1` using the character column field1, most likely because all values start with the /,
   "Bug 1034717: Catches the base == 1 case and dies"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;
