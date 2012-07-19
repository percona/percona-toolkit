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

use TableChecksum;
use TableParser;
use Quoter;
use DSNParser;
use Sandbox;
use PerconaTest;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}
else {
   plan tests => 52;
}

$sb->create_dbs($dbh, ['test']);

my $q  = new Quoter();
my $tp = new TableParser(Quoter => $q);
my $c  = new TableChecksum(Quoter=>$q);

my $t;

my %args = map { $_ => undef }
   qw(db tbl tbl_struct algorithm function crc_wid crc_type opt_slice);

throws_ok (
   sub { $c->best_algorithm( %args, algorithm => 'foo', ) },
   qr/Invalid checksum algorithm/,
   'Algorithm=foo',
);

is (
   $c->best_algorithm(
      algorithm => 'CHECKSUM',
      dbh       => '4.1.1',
   ),
   'CHECKSUM',
   'Prefers CHECKSUM',
);

is (
   $c->best_algorithm(
      dbh       => '4.1.1',
   ),
   'CHECKSUM',
   'Default is CHECKSUM',
);

is (
   $c->best_algorithm(
      algorithm => 'CHECKSUM',
      dbh       => '4.1.1',
      where     => 1,
   ),
   'BIT_XOR',
   'CHECKSUM eliminated by where',
);

is (
   $c->best_algorithm(
      algorithm => 'CHECKSUM',
      dbh       => '4.1.1',
      chunk     => 1,
   ),
   'BIT_XOR',
   'CHECKSUM eliminated by chunk',
);

is (
   $c->best_algorithm(
      algorithm => 'CHECKSUM',
      dbh       => '4.1.1',
      replicate => 1,
   ),
   'BIT_XOR',
   'CHECKSUM eliminated by replicate',
);

is (
   $c->best_algorithm(
      dbh       => '4.1.1',
      count     => 1,
   ),
   'BIT_XOR',
   'Default CHECKSUM eliminated by count',
);

is (
   $c->best_algorithm(
      algorithm => 'CHECKSUM',
      dbh       => '4.1.1',
      count     => 1,
   ),
   'CHECKSUM',
   'Explicit CHECKSUM not eliminated by count',
);

is (
   $c->best_algorithm(
      algorithm => 'CHECKSUM',
      dbh       => '4.0.0',
   ),
   'CHECKSUM',
   'Ignore version, always use CHECKSUM',
);

is (
   $c->best_algorithm(
      algorithm => 'BIT_XOR',
      dbh       => '4.1.1',
   ),
   'BIT_XOR',
   'BIT_XOR as requested',
);

is (
   $c->best_algorithm(
      algorithm => 'BIT_XOR',
      dbh       => '4.0.0',
   ),
   'BIT_XOR',
   'Ignore version, always use BIT_XOR',
);

is (
   $c->best_algorithm(
      algorithm => 'ACCUM',
      dbh       => '4.1.1',
   ),
   'ACCUM',
   'ACCUM as requested',
);

ok($c->is_hash_algorithm('ACCUM'), 'ACCUM is hash');
ok($c->is_hash_algorithm('BIT_XOR'), 'BIT_XOR is hash');
ok(!$c->is_hash_algorithm('CHECKSUM'), 'CHECKSUM is not hash');

is (
   $c->make_xor_slices(
      query   => 'FOO',
      crc_wid => 1,
   ),
   "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(FOO, 1, 1), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 1, '0')",
   'FOO XOR slices 1 wide',
);

is (
   $c->make_xor_slices(
      query   => 'FOO',
      crc_wid => 16,
   ),
   "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(FOO, 1, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0')",
   'FOO XOR slices 16 wide',
);

is (
   $c->make_xor_slices(
      query   => 'FOO',
      crc_wid => 17,
   ),
   "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(FOO, 1, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0'), "
      . "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(FOO, 17, 1), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 1, '0')",
   'FOO XOR slices 17 wide',
);

is (
   $c->make_xor_slices(
      query   => 'FOO',
      crc_wid => 32,
   ),
   "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(FOO, 1, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0'), "
      . "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(FOO, 17, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0')",
   'FOO XOR slices 32 wide',
);

is (
   $c->make_xor_slices(
      query     => 'FOO',
      crc_wid   => 32,
      opt_slice => 0,
   ),
   "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(\@crc := FOO, 1, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0'), "
      . "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(\@crc, 17, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0')",
   'XOR slice optimized in slice 0',
);

is (
   $c->make_xor_slices(
      query     => 'FOO',
      crc_wid   => 32,
      opt_slice => 1,
   ),
   "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(\@crc, 1, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0'), "
      . "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(\@crc := FOO, 17, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0')",
   'XOR slice optimized in slice 1',
);

$t = $tp->parse(load_file('t/lib/samples/sakila.film.sql'));

is (
   $c->make_row_checksum(
      function  => 'SHA1',
      tbl_struct => $t,
   ),
     q{`film_id`, `title`, `description`, `release_year`, `language_id`, `original_language_id`, `rental_duration`, `rental_rate`, `length`, `replacement_cost`, `rating`, `special_features`, `last_update` + 0 AS `last_update`, }
   . q{SHA1(CONCAT_WS('#', }
   . q{`film_id`, `title`, `description`, `release_year`, `language_id`, }
   . q{`original_language_id`, `rental_duration`, `rental_rate`, `length`, }
   . q{`replacement_cost`, `rating`, `special_features`, `last_update` + 0, }
   . q{CONCAT(ISNULL(`description`), ISNULL(`release_year`), }
   . q{ISNULL(`original_language_id`), ISNULL(`length`), }
   . q{ISNULL(`rating`), ISNULL(`special_features`))))},
   'SHA1 query for sakila.film',
);

is (
   $c->make_row_checksum(
      function      => 'FNV_64',
      tbl_struct => $t,
   ),
     q{`film_id`, `title`, `description`, `release_year`, `language_id`, `original_language_id`, `rental_duration`, `rental_rate`, `length`, `replacement_cost`, `rating`, `special_features`, `last_update` + 0 AS `last_update`, }
   . q{FNV_64(}
   . q{`film_id`, `title`, `description`, `release_year`, `language_id`, }
   . q{`original_language_id`, `rental_duration`, `rental_rate`, `length`, }
   . q{`replacement_cost`, `rating`, `special_features`, `last_update` + 0)},
   'FNV_64 query for sakila.film',
);

is (
   $c->make_row_checksum(
      function      => 'SHA1',
      tbl_struct => $t,
      cols      => [qw(film_id)],
   ),
   q{`film_id`, SHA1(`film_id`)},
   'SHA1 query for sakila.film with only one column',
);

is (
   $c->make_row_checksum(
      function      => 'SHA1',
      tbl_struct => $t,
      cols      => [qw(FILM_ID)],
   ),
   q{`film_id`, SHA1(`film_id`)},
   'Column names are case-insensitive',
);

is (
   $c->make_row_checksum(
      function      => 'SHA1',
      tbl_struct => $t,
      cols      => [qw(film_id title)],
      sep       => '%',
   ),
   q{`film_id`, `title`, SHA1(CONCAT_WS('%', `film_id`, `title`))},
   'Separator',
);

is (
   $c->make_row_checksum(
      function      => 'SHA1',
      tbl_struct => $t,
      cols      => [qw(film_id title)],
      sep       => "'%'",
   ),
   q{`film_id`, `title`, SHA1(CONCAT_WS('%', `film_id`, `title`))},
   'Bad separator',
);

is (
   $c->make_row_checksum(
      function      => 'SHA1',
      tbl_struct => $t,
      cols      => [qw(film_id title)],
      sep       => "'''",
   ),
   q{`film_id`, `title`, SHA1(CONCAT_WS('#', `film_id`, `title`))},
   'Really bad separator',
);

$t = $tp->parse(load_file('t/lib/samples/sakila.rental.float.sql'));
is (
   $c->make_row_checksum(
      function      => 'SHA1',
      tbl_struct => $t,
   ),
   q{`rental_id`, `foo`, SHA1(CONCAT_WS('#', `rental_id`, `foo`))},
   'FLOAT column is like any other',
);

is (
   $c->make_row_checksum(
      function      => 'SHA1',
      tbl_struct => $t,
      float_precision => 5,
   ),
   q{`rental_id`, ROUND(`foo`, 5), SHA1(CONCAT_WS('#', `rental_id`, ROUND(`foo`, 5)))},
   'FLOAT column is rounded to 5 places',
);

$t = $tp->parse(load_file('t/lib/samples/sakila.film.sql'));

like(
   $c->make_row_checksum(
      function   => 'SHA1',
      tbl_struct => $t,
      trim       => 1,
   ),
   qr{TRIM\(`title`\)},
   'VARCHAR column is trimmed',
);

is (
   $c->make_checksum_query(
      %args,
      db        => 'sakila',
      tbl       => 'film',
      tbl_struct => $t,
      algorithm => 'CHECKSUM',
      function      => 'SHA1',
      crc_wid   => 40,
      crc_type  => 'varchar',
   ),
   'CHECKSUM TABLE `sakila`.`film`',
   'Sakila.film CHECKSUM',
);

throws_ok (
   sub { $c->make_checksum_query(
            %args,
            db        => 'sakila',
            tbl       => 'film',
            tbl_struct => $t,
            algorithm => 'BIT_XOR',
            crc_wid   => 40,
            cols      => [qw(film_id)],
            crc_type  => 'varchar',
            function  => 'SHA1',
            algorithm => 'CHECKSUM TABLE',
         )
   },
   qr/missing checksum algorithm/,
   'Complains about bad algorithm',
);

is (
   $c->make_checksum_query(
      %args,
      db         => 'sakila',
      tbl        => 'film',
      tbl_struct => $t,
      algorithm  => 'BIT_XOR',
      function   => 'SHA1',
      crc_wid    => 40,
      cols       => [qw(film_id)],
      crc_type   => 'varchar',
   ),
   q{SELECT /*PROGRESS_COMMENT*//*CHUNK_NUM*/ COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONCAT(LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(SHA1(`film_id`), 1, }
   . q{16), 16, 10) AS UNSIGNED)), 10, 16), 16, '0'), }
   . q{LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(SHA1(`film_id`), 17, 16), 16, }
   . q{10) AS UNSIGNED)), 10, 16), 16, '0'), }
   . q{LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(SHA1(`film_id`), 33, 8), 16, }
   . q{10) AS UNSIGNED)), 10, 16), 8, '0'))), 0) AS crc }
   . q{FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/},
   'Sakila.film SHA1 BIT_XOR',
);

is (
   $c->make_checksum_query(
      %args,
      db         => 'sakila',
      tbl        => 'film',
      tbl_struct => $t,
      algorithm  => 'BIT_XOR',
      function   => 'FNV_64',
      crc_wid    => 99,
      cols       => [qw(film_id)],
      crc_type   => 'bigint',
   ),
   q{SELECT /*PROGRESS_COMMENT*//*CHUNK_NUM*/ COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONV(BIT_XOR(CAST(FNV_64(`film_id`) AS UNSIGNED)), 10, 16)), 0) AS crc }
   . q{FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/},
   'Sakila.film FNV_64 BIT_XOR',
);

is (
   $c->make_checksum_query(
      %args,
      db         => 'sakila',
      tbl        => 'film',
      tbl_struct => $t,
      algorithm  => 'BIT_XOR',
      function   => 'FNV_64',
      crc_wid    => 99,
      cols       => [qw(film_id)],
      buffer     => 1,
      crc_type   => 'bigint',
   ),
   q{SELECT SQL_BUFFER_RESULT /*PROGRESS_COMMENT*//*CHUNK_NUM*/ COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONV(BIT_XOR(CAST(FNV_64(`film_id`) AS UNSIGNED)), 10, 16)), 0) AS crc }
   . q{FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/},
   'Sakila.film FNV_64 BIT_XOR',
);

is (
   $c->make_checksum_query(
      %args,
      db         => 'sakila',
      tbl        => 'film',
      tbl_struct => $t,
      algorithm  => 'BIT_XOR',
      function   => 'CRC32',
      crc_wid    => 99,
      cols       => [qw(film_id)],
      buffer     => 1,
      crc_type   => 'int',
   ),
   q{SELECT SQL_BUFFER_RESULT /*PROGRESS_COMMENT*//*CHUNK_NUM*/ COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(`film_id`) AS UNSIGNED)), 10, 16)), 0) AS crc }
   . q{FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/},
   'Sakila.film CRC32 BIT_XOR',
);

is (
   $c->make_checksum_query(
      %args,
      db         => 'sakila',
      tbl        => 'film',
      tbl_struct => $t,
      algorithm  => 'BIT_XOR',
      function   => 'SHA1',
      crc_wid    => 40,
      cols       => [qw(film_id)],
      replicate  => 'test.checksum',
      crc_type   => 'varchar',
   ),
   q{REPLACE /*PROGRESS_COMMENT*/ INTO test.checksum }
   . q{(db, tbl, chunk, boundaries, this_cnt, this_crc) }
   . q{SELECT ?, ?, /*CHUNK_NUM*/ ?, COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONCAT(LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(SHA1(`film_id`), 1, }
   . q{16), 16, 10) AS UNSIGNED)), 10, 16), 16, '0'), }
   . q{LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(SHA1(`film_id`), 17, 16), 16, }
   . q{10) AS UNSIGNED)), 10, 16), 16, '0'), }
   . q{LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(SHA1(`film_id`), 33, 8), 16, }
   . q{10) AS UNSIGNED)), 10, 16), 8, '0'))), 0) AS crc }
   . q{FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/},
   'Sakila.film SHA1 BIT_XOR with replication',
);

is (
   $c->make_checksum_query(
      %args,
      db         => 'sakila',
      tbl        => 'film',
      tbl_struct => $t,
      algorithm  => 'ACCUM',
      function   => 'SHA1',
      crc_wid    => 40,
      crc_type   => 'varchar',
   ),
   q{SELECT /*PROGRESS_COMMENT*//*CHUNK_NUM*/ COUNT(*) AS cnt, }
   . q{COALESCE(RIGHT(MAX(@crc := CONCAT(LPAD(@cnt := @cnt + 1, 16, '0'), }
   . q{SHA1(CONCAT(@crc, SHA1(CONCAT_WS('#', }
   . q{`film_id`, `title`, `description`, `release_year`, `language_id`, }
   . q{`original_language_id`, `rental_duration`, `rental_rate`, `length`, }
   . q{`replacement_cost`, `rating`, `special_features`, `last_update` + 0, }
   . q{CONCAT(ISNULL(`description`), ISNULL(`release_year`), }
   . q{ISNULL(`original_language_id`), ISNULL(`length`), }
   . q{ISNULL(`rating`), ISNULL(`special_features`)))))))), 40), 0) AS crc }
   . q{FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/},
   'Sakila.film SHA1 ACCUM',
);

is (
   $c->make_checksum_query(
      %args,
      db         => 'sakila',
      tbl        => 'film',
      tbl_struct => $t,
      algorithm  => 'ACCUM',
      function   => 'FNV_64',
      crc_wid    => 16,
      crc_type   => 'bigint',
   ),
   q{SELECT /*PROGRESS_COMMENT*//*CHUNK_NUM*/ COUNT(*) AS cnt, }
   . q{COALESCE(RIGHT(MAX(@crc := CONCAT(LPAD(@cnt := @cnt + 1, 16, '0'), }
   . q{CONV(CAST(FNV_64(CONCAT(@crc, FNV_64(}
   . q{`film_id`, `title`, `description`, `release_year`, `language_id`, }
   . q{`original_language_id`, `rental_duration`, `rental_rate`, `length`, }
   . q{`replacement_cost`, `rating`, `special_features`, `last_update` + 0}
   . q{))) AS UNSIGNED), 10, 16))), 16), 0) AS crc }
   . q{FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/},
   'Sakila.film FNV_64 ACCUM',
);

is (
   $c->make_checksum_query(
      %args,
      db         => 'sakila',
      tbl        => 'film',
      tbl_struct => $t,
      algorithm  => 'ACCUM',
      function   => 'CRC32',
      crc_wid    => 16,
      crc_type   => 'int',
      cols       => [qw(film_id)],
   ),
   q{SELECT /*PROGRESS_COMMENT*//*CHUNK_NUM*/ COUNT(*) AS cnt, }
   . q{COALESCE(RIGHT(MAX(@crc := CONCAT(LPAD(@cnt := @cnt + 1, 16, '0'), }
   . q{CONV(CAST(CRC32(CONCAT(@crc, CRC32(`film_id`}
   . q{))) AS UNSIGNED), 10, 16))), 16), 0) AS crc }
   . q{FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/},
   'Sakila.film CRC32 ACCUM',
);

is (
   $c->make_checksum_query(
      %args,
      db         => 'sakila',
      tbl        => 'film',
      tbl_struct => $t,
      algorithm  => 'ACCUM',
      function   => 'SHA1',
      crc_wid    => 40,
      replicate  => 'test.checksum',
      crc_type   => 'varchar',
   ),
   q{REPLACE /*PROGRESS_COMMENT*/ INTO test.checksum }
   . q{(db, tbl, chunk, boundaries, this_cnt, this_crc) }
   . q{SELECT ?, ?, /*CHUNK_NUM*/ ?, COUNT(*) AS cnt, }
   . q{COALESCE(RIGHT(MAX(@crc := CONCAT(LPAD(@cnt := @cnt + 1, 16, '0'), }
   . q{SHA1(CONCAT(@crc, SHA1(CONCAT_WS('#', }
   . q{`film_id`, `title`, `description`, `release_year`, `language_id`, }
   . q{`original_language_id`, `rental_duration`, `rental_rate`, `length`, }
   . q{`replacement_cost`, `rating`, `special_features`, `last_update` + 0, }
   . q{CONCAT(ISNULL(`description`), ISNULL(`release_year`), }
   . q{ISNULL(`original_language_id`), ISNULL(`length`), }
   . q{ISNULL(`rating`), ISNULL(`special_features`)))))))), 40), 0) AS crc }
   . q{FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/},
   'Sakila.film SHA1 ACCUM with replication',
);

is ( $c->crc32('hello world'), 222957957, 'CRC32 of hello world');

# #############################################################################
# Sandbox tests.
# #############################################################################
like(
   $c->choose_hash_func(
      dbh => $dbh,
   ),
   qr/CRC32|FNV_64|MD5/,
   'CRC32, FNV_64 or MD5 is default',
);

like(
   $c->choose_hash_func(
      dbh      => $dbh,
      function => 'SHA99',
   ),
   qr/CRC32|FNV_64|MD5/,
   'SHA99 does not exist so I get CRC32 or friends',
);

is(
   $c->choose_hash_func(
      dbh      => $dbh,
      function => 'MD5',
   ),
   'MD5',
   'MD5 requested and MD5 granted',
);

is(
   $c->optimize_xor(
      dbh      => $dbh,
      function => 'SHA1',
   ),
   '2',
   'SHA1 slice is 2',
);

is(
   $c->optimize_xor(
      dbh      => $dbh,
      function => 'MD5',
   ),
   '1',
   'MD5 slice is 1',
);

is_deeply(
   [$c->get_crc_type($dbh, 'CRC32')],
   [qw(int 10)],
   'Type and length of CRC32'
);

is_deeply(
   [$c->get_crc_type($dbh, 'MD5')],
   [qw(varchar 32)],
   'Type and length of MD5'
);

# #############################################################################
# Issue 94: Enhance mk-table-checksum, add a --ignorecols option
# #############################################################################
$sb->load_file('master', 't/lib/samples/issue_94.sql');
$t= $tp->parse( $tp->get_create_table($dbh, 'test', 'issue_94') );
my $query = $c->make_checksum_query(
   db         => 'test',
   tbl        => 'issue_47',
   tbl_struct => $t,
   algorithm  => 'ACCUM',
   function   => 'CRC32',
   crc_wid    => 16,
   crc_type   => 'int',
   opt_slice  => undef,
   cols       => undef,
   sep        => '#',
   replicate  => undef,
   precision  => undef,
   trim       => undef,
   ignorecols => {'c'=>1},
);
is($query,
   'SELECT /*PROGRESS_COMMENT*//*CHUNK_NUM*/ COUNT(*) AS cnt, COALESCE(RIGHT(MAX(@crc := CONCAT(LPAD(@cnt := @cnt + 1, 16, \'0\'), CONV(CAST(CRC32(CONCAT(@crc, CRC32(CONCAT_WS(\'#\', `a`, `b`)))) AS UNSIGNED), 10, 16))), 16), 0) AS crc FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/',
   'Ignores specified columns');

$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
