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

use RowChecksum;
use TableParser;
use Quoter;
use MySQLDump;
use DSNParser;
use OptionParser;
use Sandbox;
use PerconaTest;

my $dp = DSNParser->new(opts=>$dsn_opts);
my $sb = Sandbox->new(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}
else {
   plan tests => 28;
}

$sb->create_dbs($dbh, ['test']);

my $q  = Quoter->new();
my $tp = TableParser->new(Quoter => $q);
my $du = MySQLDump->new();
my $o  = OptionParser->new(description => 'NibbleIterator');
$o->get_specs("$trunk/bin/pt-table-checksum");

my $c  = RowChecksum->new(
   OptionParser  => $o,
   Quoter        => $q,
);

# ############################################################################
# _make_xor_slices
# ############################################################################
is(
   $c->_make_xor_slices(
      row_checksum => 'FOO',
      crc_width    => 1,
   ),
   "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(FOO, 1, 1), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 1, '0')",
   'FOO XOR slices 1 wide',
);

is(
   $c->_make_xor_slices(
      row_checksum => 'FOO',
      crc_width    => 16,
   ),
   "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(FOO, 1, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0')",
   'FOO XOR slices 16 wide',
);

is(
   $c->_make_xor_slices(
      row_checksum => 'FOO',
      crc_width    => 17,
   ),
   "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(FOO, 1, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0'), "
      . "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(FOO, 17, 1), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 1, '0')",
   'FOO XOR slices 17 wide',
);

is(
   $c->_make_xor_slices(
      row_checksum => 'FOO',
      crc_width    => 32,
   ),
   "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(FOO, 1, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0'), "
      . "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(FOO, 17, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0')",
   'FOO XOR slices 32 wide',
);

is(
   $c->_make_xor_slices(
      row_checksum => 'FOO',
      crc_width    => 32,
      opt_slice    => 0,
   ),
   "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(\@crc := FOO, 1, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0'), "
      . "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(\@crc, 17, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0')",
   'XOR slice optimized in slice 0',
);

is(
   $c->_make_xor_slices(
      row_checksum => 'FOO',
      crc_width    => 32,
      opt_slice    => 1,
   ),
   "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(\@crc, 1, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0'), "
      . "LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(\@crc := FOO, 17, 16), 16, 10) "
      . "AS UNSIGNED)), 10, 16), 16, '0')",
   'XOR slice optimized in slice 1',
);

# ############################################################################
# make_row_checksum
# ############################################################################
my $tbl = {
   db         => 'sakila',
   tbl        => 'film',
   tbl_struct => $tp->parse(load_file('t/lib/samples/sakila.film.sql')),
};

is(
   $c->make_row_checksum(
      tbl  => $tbl,
      func => 'SHA1',
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

is(
   $c->make_row_checksum(
      tbl  => $tbl,
      func => 'FNV_64',
   ),
     q{`film_id`, `title`, `description`, `release_year`, `language_id`, `original_language_id`, `rental_duration`, `rental_rate`, `length`, `replacement_cost`, `rating`, `special_features`, `last_update` + 0 AS `last_update`, }
   . q{FNV_64(}
   . q{`film_id`, `title`, `description`, `release_year`, `language_id`, }
   . q{`original_language_id`, `rental_duration`, `rental_rate`, `length`, }
   . q{`replacement_cost`, `rating`, `special_features`, `last_update` + 0)},
   'FNV_64 query for sakila.film',
);

is(
   $c->make_row_checksum(
      tbl  => $tbl,
      func => 'SHA1',
      cols => [qw(film_id)],
   ),
   q{`film_id`, SHA1(`film_id`)},
   'SHA1 query for sakila.film with only one column',
);

is(
   $c->make_row_checksum(
      tbl  => $tbl,
      func => 'SHA1',
      cols => [qw(FILM_ID)],
   ),
   q{`film_id`, SHA1(`film_id`)},
   'Column names are case-insensitive',
);

is(
   $c->make_row_checksum(
      tbl  => $tbl,
      func => 'SHA1',
      cols => [qw(film_id title)],
      sep  => '%',
   ),
   q{`film_id`, `title`, SHA1(CONCAT_WS('%', `film_id`, `title`))},
   'Separator',
);

is(
   $c->make_row_checksum(
      tbl  => $tbl,
      func => 'SHA1',
      cols => [qw(film_id title)],
      sep  => "'%'",
   ),
   q{`film_id`, `title`, SHA1(CONCAT_WS('%', `film_id`, `title`))},
   'Bad separator',
);

is(
   $c->make_row_checksum(
      tbl  => $tbl,
      func => 'SHA1',
      cols => [qw(film_id title)],
      sep  => "'''",
   ),
   q{`film_id`, `title`, SHA1(CONCAT_WS('#', `film_id`, `title`))},
   'Really bad separator',
);

# sakila.rental
$tbl = {
   db         => 'sakila',
   tbl        => 'rental',
   tbl_struct => $tp->parse(load_file('t/lib/samples/sakila.rental.float.sql')),
};

is(
   $c->make_row_checksum(
      tbl  => $tbl,
      func => 'SHA1',
   ),
   q{`rental_id`, `foo`, SHA1(CONCAT_WS('#', `rental_id`, `foo`))},
   'FLOAT column is like any other',
);

is(
   $c->make_row_checksum(
      tbl  => $tbl,
      func => 'SHA1',
      float_precision => 5,
   ),
   q{`rental_id`, ROUND(`foo`, 5), SHA1(CONCAT_WS('#', `rental_id`, ROUND(`foo`, 5)))},
   'FLOAT column is rounded to 5 places',
);

# sakila.film
$tbl = {
   db         => 'sakila',
   tbl        => 'film',
   tbl_struct => $tp->parse(load_file('t/lib/samples/sakila.film.sql')),
};

like(
   $c->make_row_checksum(
      tbl  => $tbl,
      func => 'SHA1',
      trim => 1,
   ),
   qr{TRIM\(`title`\)},
   'VARCHAR column is trimmed',
);

# ############################################################################
# make_chunk_checksum
# ############################################################################
is(
   $c->make_chunk_checksum(
      tbl      => $tbl,
      func     => 'SHA1',
      crc_width=> 40,
      cols     => [qw(film_id)],
      crc_type => 'varchar',
   ),
   q{COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONCAT(LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(SHA1(`film_id`), 1, }
   . q{16), 16, 10) AS UNSIGNED)), 10, 16), 16, '0'), }
   . q{LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(SHA1(`film_id`), 17, 16), 16, }
   . q{10) AS UNSIGNED)), 10, 16), 16, '0'), }
   . q{LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(SHA1(`film_id`), 33, 8), 16, }
   . q{10) AS UNSIGNED)), 10, 16), 8, '0'))), 0) AS crc},
   'sakila.film SHA1',
);

is(
   $c->make_chunk_checksum(
      tbl      => $tbl,
      func     => 'FNV_64',
      crc_width=> 99,
      cols     => [qw(film_id)],
      crc_type => 'bigint',
   ),
   q{COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONV(BIT_XOR(CAST(FNV_64(`film_id`) AS UNSIGNED)), 10, 16)), 0) AS crc},
   'sakila.film FNV_64',
);

is(
   $c->make_chunk_checksum(
      tbl      => $tbl,
      func     => 'FNV_64',
      crc_width=> 99,
      cols     => [qw(film_id)],
      buffer   => 1,
      crc_type => 'bigint',
   ),
   q{COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONV(BIT_XOR(CAST(FNV_64(`film_id`) AS UNSIGNED)), 10, 16)), 0) AS crc},
   'sakila.film FNV_64',
);

is(
   $c->make_chunk_checksum(
      tbl      => $tbl,
      func     => 'CRC32',
      crc_width=> 99,
      cols     => [qw(film_id)],
      buffer   => 1,
      crc_type => 'int',
   ),
   q{COUNT(*) AS cnt, }
   . q{COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(`film_id`) AS UNSIGNED)), 10, 16)), 0) AS crc},
   'sakila.film CRC32',
);

# #############################################################################
# Sandbox tests.
# #############################################################################
like(
   $c->_get_hash_func(
      dbh => $dbh,
   ),
   qr/CRC32|FNV_64|MD5/,
   'CRC32, FNV_64 or MD5 is default',
);

like(
   $c->_get_hash_func(
      dbh  => $dbh,
      func => 'SHA99',
   ),
   qr/CRC32|FNV_64|MD5/,
   'SHA99 does not exist so I get CRC32 or friends',
);

@ARGV = qw(--function MD5);
$o->get_opts();
is(
   $c->_get_hash_func(
      dbh  => $dbh,
      func => 'MD5',
   ),
   'MD5',
   'MD5 requested and MD5 granted',
);
@ARGV = qw();
$o->get_opts();

is(
   $c->_optimize_xor(
      dbh  => $dbh,
      func => 'SHA1',
   ),
   '2',
   'SHA1 slice is 2',
);

is(
   $c->_optimize_xor(
      dbh  => $dbh,
      func => 'MD5',
   ),
   '1',
   'MD5 slice is 1',
);

is(
   $c->_get_crc_type(
      dbh  => $dbh,
      func => 'CRC32',
   ),
   'int',
   'CRC32 type'
);

is(
   $c->_get_crc_type(
      dbh  => $dbh,
      func => 'MD5',
   ),
   'varchar',
   'MD5 type'
);

# #############################################################################
# Issue 94: Enhance mk-table-checksum, add a --ignorecols option
# #############################################################################
$sb->load_file('master', 't/lib/samples/issue_94.sql');
$tbl = {
   db         => 'test',
   tbl        => 'issue_94',
   tbl_struct => $tp->parse($du->get_create_table($dbh, $q, 'test', 'issue_94')),
};
my $query = $c->make_chunk_checksum(
   tbl        => $tbl,
   func       => 'CRC32',
   crc_width  => 16,
   crc_type   => 'int',
   opt_slice  => undef,
   cols       => undef,
   sep        => '#',
   replicate  => undef,
   precision  => undef,
   trim       => undef,
   ignorecols => {'c'=>1},
);
is(
   $query,
   "COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `a`, `b`)) AS UNSIGNED)), 10, 16)), 0) AS crc",
   'Ignores specified columns'
);

# ############################################################################
# Done.
# ############################################################################
$sb->wipe_clean($dbh);
exit;
