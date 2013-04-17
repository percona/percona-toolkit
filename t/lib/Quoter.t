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

use Quoter;
use PerconaTest;
use DSNParser;
use Sandbox;
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

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
is( $q->quote_val('0x89504E470', is_char => 0), '0x89504E470', 'hex string, with is_char => 0');
is( $q->quote_val('0x89504E470', is_char => 1), "'0x89504E470'", 'hex string, with is_char => 1');
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

is_deeply(
   [$q->split_unquote("`db`.`tb``l```")],
   [qw(db tb`l`)],
   'splits with a quoted db.tbl ad embedded quotes',
);

#TODO: {
#   local $::TODO = "Embedded periods not yet supported";
#   is_deeply(
#      [$q->split_unquote("`d.b`.`tbl`")],
#      [qw(d.b tbl)],
#      'splits with embedded periods: `d.b`.`tbl`',
#   );
#}

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

is(
   $q->serialize_list( () ),
   undef,
   'Serialize empty list returns undef'
);
   
binmode(STDOUT, ':utf8')
   or die "Can't binmode(STDOUT, ':utf8'): $OS_ERROR";
binmode(STDERR, ':utf8')
   or die "Can't binmode(STDERR, ':utf8'): $OS_ERROR";

# Prevent "Wide character in print at Test/Builder.pm" warnings.
binmode Test::More->builder->$_(), ':encoding(UTF-8)'
   for qw(output failure_output);

my @latin1_serialize_tests = (
   [ 'a' ],
   [ 'a', 'b', ],
   [ 'a,', 'b', ],  # trailing comma
   [ ',a', 'b', ],  # leading comma
   [ 'a', ',b' ],
   [ 0 ],
   [ 0, 0 ],
   [ 1, 2 ],
   [ '' ],  # emptry string
   [ '', '', '', ],
   [ undef ],  # NULL
   [ undef, undef ],
   [ undef, '' ],
   [ '\N' ],  # literal \N
   [ "un caf\x{e9} na\x{ef}ve" ],  # Latin-1
   [ "\\," ],
   [ '\\' ],
   [ q/"abc\\", 'def'/ ],  # Brian's pathalogical case
);

my @utf8_serialize_tests = (
   [ "\x{30cb} \x{e8}" ],  # UTF-8
);

SKIP: {
   skip 'Cannot connect to sandbox master', scalar @latin1_serialize_tests
      unless $dbh;

   $dbh->do('CREATE DATABASE IF NOT EXISTS serialize_test');
   $dbh->do('DROP TABLE IF EXISTS serialize_test.serialize');
   $dbh->do('CREATE TABLE serialize_test.serialize (id INT, textval TEXT, blobval BLOB)');

   my $sth = $dbh->prepare(
      "INSERT INTO serialize_test.serialize VALUES (?, ?, ?)"
   );

   for my $test_index ( 0..$#latin1_serialize_tests ) {

      # Flat, friendly name for the test string
      my $flat_string
         =  "["
         . join( "][",
               map { defined($_) ? $_ : 'undef' }
               @{$latin1_serialize_tests[$test_index]})
         . "]";
      $flat_string =~ s/\n/\\n/g;

      # INSERT the serialized list of values.
      my $ser = $q->serialize_list( @{$latin1_serialize_tests[$test_index]} );
      $sth->execute($test_index, $ser, $ser);

      # SELECT back the values and deserialize them. 
      my ($text_string) = $dbh->selectrow_array(
         "SELECT textval FROM serialize_test.serialize WHERE id=$test_index");
      my @text_parts = $q->deserialize_list($text_string);

      is_deeply(
         \@text_parts,
         $latin1_serialize_tests[$test_index],
         "Serialize $flat_string"
      ) or diag(Dumper($text_string, \@text_parts));
   }
};

my $utf8_dbh = $sb->get_dbh_for('master');
$utf8_dbh->{mysql_enable_utf8} = 1;
$utf8_dbh->do("SET NAMES 'utf8'");
SKIP: {
   skip 'Cannot connect to sandbox master', scalar @utf8_serialize_tests
      unless $utf8_dbh;
   skip 'DBD::mysql 3.0007 has UTF-8 bug', scalar @utf8_serialize_tests
      if $DBD::mysql::VERSION le '3.0007';

   $utf8_dbh->do("DROP TABLE serialize_test.serialize");
   $utf8_dbh->do("CREATE TABLE serialize_test.serialize (id INT, textval TEXT, blobval BLOB) CHARSET='utf8'");

   my $sth = $utf8_dbh->prepare(
      "INSERT INTO serialize_test.serialize VALUES (?, ?, ?)"
   );

   for my $test_index ( 0..$#utf8_serialize_tests ) {

      # Flat, friendly name for the test string
      my $flat_string
         =  "["
         . join( "][",
               map { defined($_) ? $_ : 'undef' }
               @{$utf8_serialize_tests[$test_index]})
         . "]";
      $flat_string =~ s/\n/\\n/g;

      # INSERT the serialized list of values.
      my $ser = $q->serialize_list( @{$utf8_serialize_tests[$test_index]} );
      $sth->execute($test_index, $ser, $ser);

      # SELECT back the values and deserialize them. 
      my ($text_string) = $utf8_dbh->selectrow_array(
         "SELECT textval FROM serialize_test.serialize WHERE id=$test_index");
      my @text_parts = $q->deserialize_list($text_string);

      is_deeply(
         \@text_parts,
         $utf8_serialize_tests[$test_index],
         "Serialize UTF-8 $flat_string"
      ) or diag(Dumper($text_string, \@text_parts));
   }

   $utf8_dbh->disconnect();
};

# ###########################################################################
# Done.
# ###########################################################################
if ( $dbh ) {
   $sb->wipe_clean($dbh);
   $dbh->disconnect();
}
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
