#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 47;

use Quoter;
use PerconaTest;

my $q = new Quoter;

is(
   $q->quote('a'),
   '`a`',
   'Simple quote OK',
);

is(
   $q->quote('a','b'),
   '`a`.`b`',
   'multi value',
);

is(
   $q->quote('`a`'),
   '```a```',
   'already quoted',
);

is(
   $q->quote('a`b'),
   '`a``b`',
   'internal quote',
);

is(
   $q->quote('my db', 'my tbl'),
   '`my db`.`my tbl`',
   'quotes db with space and tbl with space'
);

is( $q->quote_val(1), "'1'", 'number' );
is( $q->quote_val('001'), "'001'", 'number with leading zero' );
# is( $q->quote_val(qw(1 2 3)), '1, 2, 3', 'three numbers');
is( $q->quote_val(qw(a)), "'a'", 'letter');
is( $q->quote_val("a'"), "'a\\''", 'letter with quotes');
is( $q->quote_val(undef), 'NULL', 'NULL');
is( $q->quote_val(''), "''", 'Empty string');
is( $q->quote_val('\\\''), "'\\\\\\\''", 'embedded backslash');
# is( $q->quote_val(42, 0), "'42'", 'non-numeric number' );
# is( $q->quote_val(42, 1), "42", 'number is numeric' );
is( $q->quote_val('123-abc'), "'123-abc'", 'looks numeric but is string');
is( $q->quote_val('123abc'), "'123abc'", 'looks numeric but is string');
is( $q->quote_val('0x89504E470'), '0x89504E470', 'hex string');
is( $q->quote_val('0x89504I470'), "'0x89504I470'", 'looks like hex string');
is( $q->quote_val('eastside0x3'), "'eastside0x3'", 'looks like hex str (issue 1110');

# Splitting DB and tbl apart
is_deeply(
   [$q->split_unquote("`db`.`tbl`")],
   [qw(db tbl)],
   'splits with a quoted db.tbl',
);

is_deeply(
   [$q->split_unquote("db.tbl")],
   [qw(db tbl)],
   'splits with a db.tbl',
);

is_deeply(
   [$q->split_unquote("tbl")],
   [undef, 'tbl'],
   'splits without a db',
);

is_deeply(
   [$q->split_unquote("tbl", "db")],
   [qw(db tbl)],
   'splits with a db',
);

is( $q->literal_like('foo'), "'foo'", 'LIKE foo');
is( $q->literal_like('foo_bar'), "'foo\\_bar'", 'LIKE foo_bar');
is( $q->literal_like('foo%bar'), "'foo\\%bar'", 'LIKE foo%bar');
is( $q->literal_like('v_b%a c_'), "'v\\_b\\%a c\\_'", 'LIKE v_b%a c_');

is( $q->join_quote('db', 'tbl'), '`db`.`tbl`', 'join_merge(db, tbl)' );
is( $q->join_quote(undef, 'tbl'), '`tbl`', 'join_merge(undef, tbl)'  );
is( $q->join_quote('db', 'foo.tbl'), '`foo`.`tbl`', 'join_merge(db, foo.tbl)' );
is( $q->join_quote('`db`', '`tbl`'), '`db`.`tbl`', 'join_merge(`db`, `tbl`)' );
is( $q->join_quote(undef, '`tbl`'), '`tbl`', 'join_merge(undef, `tbl`)'  );
is( $q->join_quote('`db`', '`foo`.`tbl`'), '`foo`.`tbl`', 'join_merge(`db`, `foo`.`tbl`)' );

# ###########################################################################
# (de)serialize_list
# ###########################################################################

my @serialize_tests = (
   [ 'a', 'b', ],
   [ 'a,', 'b', ],
   [ "a,\\\nc\nas", 'b', ],
   [ 'a\\\,a', 'c', ],
   [ 'a\\\\,a', 'c', ],
   [ 'a\\\\\,aa', 'c', ],
   [ 'a\\\\\\,aa', 'c', ],
   [ 'a\\\,a,a', 'c,d,e,d,', ],
   [ "\\\,\x{e8},a", '!!!!__!*`,`\\', ], # Latin-1
   [ "\x{30cb}\\\,\x{e8},a", '!!!!__!*`,`\\', ], # UTF-8
   [ ",,,,,,,,,,,,,,", ",", ],
   [ "\\,\\,\\,\\,\\,\\,\\,\\,\\,\\,\\,,,,\\", ":(", ],
   [ "asdfa", "\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\,a", ],
   [ 1, 2 ],
   [ 7, 9 ],
   [ '', '', '', ],
);

use DSNParser;
use Sandbox;
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
SKIP: {
   skip 'Cannot connect to sandbox master', scalar @serialize_tests unless $dbh;

   # Prevent "Wide character in print at Test/Builder.pm" warnings.
   binmode Test::More->builder->$_(), ':encoding(UTF-8)'
      for qw(output failure_output);

   $dbh->do('CREATE DATABASE IF NOT EXISTS serialize_test');
   $dbh->do('DROP TABLE IF EXISTS serialize_test.serialize');
   $dbh->do('CREATE TABLE serialize_test.serialize (id INT, foo TEXT)');

   my $sth    = $dbh->prepare(
      "INSERT INTO serialize_test.serialize (id, foo) VALUES (?, ?)"
   );
   my $selsth = $dbh->prepare(
      "SELECT foo FROM serialize_test.serialize WHERE id=? LIMIT 1"
   );

   for my $test_index ( 0..$#serialize_tests ) {
      my $ser = $q->serialize_list( @{$serialize_tests[$test_index]} );

      # Bit of a hack, but we want to test both of Perl's internal encodings
      # for correctness.
      local $dbh->{'mysql_enable_utf8'} = 1 if utf8::is_utf8($ser);

      $sth->execute($test_index, $ser);
      $selsth->execute($test_index);

      my $flat_string = "@{$serialize_tests[$test_index]}";
      $flat_string =~ s/\n/\\n/g;

      is_deeply(
         [ $q->deserialize_list($selsth->fetchrow_array()) ],
         $serialize_tests[$test_index],
         "Serialize $flat_string"
      );
   }

   $sth->finish();
   $selsth->finish();

   $dbh->do("DROP DATABASE serialize_test");

   $dbh->disconnect();
};

# ###########################################################################
# Done.
# ###########################################################################
exit;
