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

use ChangeHandler;
use Quoter;
use DSNParser;
use Sandbox;
use PerconaTest;

my $dp  = new DSNParser(opts => $dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');

throws_ok(
   sub { new ChangeHandler() },
   qr/I need a Quoter/,
   'Needs a Quoter',
);

my @rows;
my @dbhs;
my $q  = new Quoter();
my $ch = new ChangeHandler(
   Quoter    => $q,
   right_db  => 'test',  # dst
   right_tbl => 'foo',
   left_db   => 'test',  # src
   left_tbl  => 'test1',
   actions   => [ sub { push @rows, $_[0]; push @dbhs, $_[1]; } ],
   replace   => 0,
   queue     => 0,
);

$ch->change('INSERT', { a => 1, b => 2 }, [qw(a)] );

is_deeply(\@rows,
   ["INSERT INTO `test`.`foo`(`a`, `b`) VALUES ('1', '2')",],
   'First row',
);

$ch->change(undef, { a => 1, b => 2 }, [qw(a)] );

is_deeply(
   \@rows,
   ["INSERT INTO `test`.`foo`(`a`, `b`) VALUES ('1', '2')",],
   'Skips undef action'
);


is_deeply(\@rows,
   ["INSERT INTO `test`.`foo`(`a`, `b`) VALUES ('1', '2')",],
   'First row',
);

$ch->{queue} = 1;

$ch->change('DELETE', { a => 1, b => 2 }, [qw(a)] );

is_deeply(\@rows,
   ["INSERT INTO `test`.`foo`(`a`, `b`) VALUES ('1', '2')",],
   'Second row not there yet',
);

$ch->process_rows(1);

is_deeply(\@rows,
   [
   "INSERT INTO `test`.`foo`(`a`, `b`) VALUES ('1', '2')",
   "DELETE FROM `test`.`foo` WHERE `a`='1' LIMIT 1",
   ],
   'Second row there',
);
$ch->{queue} = 2;

$ch->change('UPDATE', { a => 1, b => 2 }, [qw(a)] );
$ch->process_rows(1);

is_deeply(\@rows,
   [
   "INSERT INTO `test`.`foo`(`a`, `b`) VALUES ('1', '2')",
   "DELETE FROM `test`.`foo` WHERE `a`='1' LIMIT 1",
   ],
   'Third row not there',
);

$ch->process_rows();

is_deeply(\@rows,
   [
   "INSERT INTO `test`.`foo`(`a`, `b`) VALUES ('1', '2')",
   "DELETE FROM `test`.`foo` WHERE `a`='1' LIMIT 1",
   "UPDATE `test`.`foo` SET `b`='2' WHERE `a`='1' LIMIT 1",
   ],
   'All rows',
);

is_deeply(
   { $ch->get_changes() },
   { REPLACE => 0, DELETE => 1, INSERT => 1, UPDATE => 1 },
   'Changes were recorded',
);


# #############################################################################
# Test that the optional dbh is passed through to our actions.
# #############################################################################
@rows = ();
@dbhs = ();
$ch->{queue} = 0;
# 42 is a placeholder for the dbh arg.
$ch->change('INSERT', { a => 1, b => 2 }, [qw(a)], 42);

is_deeply(
   \@dbhs,
   [42],
   'dbh passed through change()'
);

$ch->{queue} = 1;

@rows = ();
@dbhs = ();
$ch->change('INSERT', { a => 1, b => 2 }, [qw(a)], 42);

is_deeply(
   \@dbhs,
   [],
   'No dbh yet'
);

$ch->process_rows(1);

is_deeply(
   \@dbhs,
   [42],
   'dbh passed through process_rows()'
);


# #############################################################################
# Test switching direction (swap src/dst).
# #############################################################################
$ch = new ChangeHandler(
   Quoter    => $q,
   left_db   => 'test',
   left_tbl  => 'left_foo',
   right_db  => 'test',
   right_tbl => 'right_foo',
   actions   => [ sub { push @rows, $_[0]; push @dbhs, $_[1]; } ],
   replace   => 0,
   queue     => 0,
);

@rows = ();
@dbhs = ();

# Default is left=source.
$ch->set_src('right');
is(
   $ch->src,
   '`test`.`right_foo`',
   'Changed src',
);
is(
   $ch->dst,
   '`test`.`left_foo`',
   'Changed dst'
);

$ch->change('INSERT', { a => 1, b => 2 }, [qw(a)] );

is_deeply(
   \@rows,
   ["INSERT INTO `test`.`left_foo`(`a`, `b`) VALUES ('1', '2')",],
   'INSERT new dst',
);

$ch->change('DELETE', { a => 1, b => 2 }, [qw(a)] );
$ch->process_rows(1);
is_deeply(\@rows,
   [
   "INSERT INTO `test`.`left_foo`(`a`, `b`) VALUES ('1', '2')",
   "DELETE FROM `test`.`left_foo` WHERE `a`='1' LIMIT 1",
   ],
   'DELETE new dst',
);


# #############################################################################
# Test fetch_back().
# #############################################################################
SKIP: {
   skip 'Cannot connect to sandbox master', 1 unless $master_dbh;

   $master_dbh->do('CREATE DATABASE IF NOT EXISTS test');

   $ch = new ChangeHandler(
      Quoter    => $q,
      right_db  => 'test',  # dst
      right_tbl => 'foo',
      left_db   => 'test',  # src
      left_tbl  => 'test1',
      actions   => [ sub { push @rows, $_[0]; push @dbhs, $_[1]; } ],
      replace   => 0,
      queue     => 0,
   );

   @rows = ();
   $ch->{queue} = 0;
   $ch->fetch_back($master_dbh);
   `/tmp/12345/use < $trunk/t/lib/samples/before-TableSyncChunk.sql`;
   # This should cause it to fetch the row from test.test1 where a=1
   $ch->change('UPDATE', { a => 1, __foo => 'bar' }, [qw(a)] );
   $ch->change('DELETE', { a => 1, __foo => 'bar' }, [qw(a)] );
   $ch->change('INSERT', { a => 1, __foo => 'bar' }, [qw(a)] );
   is_deeply(
      \@rows,
      [
         "UPDATE `test`.`foo` SET `b`='en' WHERE `a`='1' LIMIT 1",
         "DELETE FROM `test`.`foo` WHERE `a`='1' LIMIT 1",
         "INSERT INTO `test`.`foo`(`a`, `b`) VALUES ('1', 'en')",
      ],
      'Fetch-back',
   );
}

# #############################################################################
# Issue 371: Make mk-table-sync preserve column order in SQL
# #############################################################################
my $row = {
   id  => 1,
   foo => 'foo',
   bar => 'bar',
};
my $tbl_struct = {
   col_posn => { id=>0, foo=>1, bar=>2 },
};
$ch = new ChangeHandler(
   Quoter     => $q,
   right_db   => 'test',       # dst
   right_tbl  => 'issue_371',
   left_db    => 'test',       # src
   left_tbl   => 'issue_371',
   actions    => [ sub { push @rows, @_ } ],
   replace    => 0,
   queue      => 0,
   tbl_struct => $tbl_struct,
);

@rows = ();
@dbhs = ();

is(
   $ch->make_INSERT($row, [qw(id foo bar)]),
   "INSERT INTO `test`.`issue_371`(`id`, `foo`, `bar`) VALUES ('1', 'foo', 'bar')",
   'make_INSERT() preserves column order'
);

is(
   $ch->make_REPLACE($row, [qw(id foo bar)]),
   "REPLACE INTO `test`.`issue_371`(`id`, `foo`, `bar`) VALUES ('1', 'foo', 'bar')",
   'make_REPLACE() preserves column order'
);

is(
   $ch->make_UPDATE($row, [qw(id foo)]),
   "UPDATE `test`.`issue_371` SET `bar`='bar' WHERE `id`='1' AND `foo`='foo' LIMIT 1",
   'make_UPDATE() preserves column order'
);

is(
   $ch->make_DELETE($row, [qw(id foo bar)]),
   "DELETE FROM `test`.`issue_371` WHERE `id`='1' AND `foo`='foo' AND `bar`='bar' LIMIT 1",
   'make_DELETE() preserves column order'
);

# Test what happens if the row has a column that not in the tbl struct.
$row->{other_col} = 'zzz';

is(
   $ch->make_INSERT($row, [qw(id foo bar)]),
   "INSERT INTO `test`.`issue_371`(`id`, `foo`, `bar`, `other_col`) VALUES ('1', 'foo', 'bar', 'zzz')",
   'make_INSERT() preserves column order, with col not in tbl'
);

is(
   $ch->make_REPLACE($row, [qw(id foo bar)]),
   "REPLACE INTO `test`.`issue_371`(`id`, `foo`, `bar`, `other_col`) VALUES ('1', 'foo', 'bar', 'zzz')",
   'make_REPLACE() preserves column order, with col not in tbl'
);

is(
   $ch->make_UPDATE($row, [qw(id foo)]),
   "UPDATE `test`.`issue_371` SET `bar`='bar', `other_col`='zzz' WHERE `id`='1' AND `foo`='foo' LIMIT 1",
   'make_UPDATE() preserves column order, with col not in tbl'
);

delete $row->{other_col};

SKIP: {
   skip 'Cannot connect to sandbox master', 3 unless $master_dbh;

   $master_dbh->do('DROP TABLE IF EXISTS test.issue_371');
   $master_dbh->do('CREATE TABLE test.issue_371 (id INT, foo varchar(16), bar char)');
   $master_dbh->do("INSERT INTO test.issue_371 VALUES (1,'foo','a'),(2,'bar','b')");

   $ch->fetch_back($master_dbh);

   is(
      $ch->make_INSERT($row, [qw(id foo)]),
      "INSERT INTO `test`.`issue_371`(`id`, `foo`, `bar`) VALUES ('1', 'foo', 'a')",
      'make_INSERT() preserves column order, with fetch-back'
   );

   is(
      $ch->make_REPLACE($row, [qw(id foo)]),
      "REPLACE INTO `test`.`issue_371`(`id`, `foo`, `bar`) VALUES ('1', 'foo', 'a')",
      'make_REPLACE() preserves column order, with fetch-back'
   );

   is(
      $ch->make_UPDATE($row, [qw(id foo)]),
      "UPDATE `test`.`issue_371` SET `bar`='a' WHERE `id`='1' AND `foo`='foo' LIMIT 1",
      'make_UPDATE() preserves column order, with fetch-back'
   );
};

# #############################################################################
# Issue 641: Make mk-table-sync use hex for binary/blob data
# #############################################################################
$tbl_struct = {
   cols     => [qw(a x b)],
   type_for => {a=>'int', x=>'blob', b=>'varchar'},
};
$ch = new ChangeHandler(
   Quoter     => $q,
   left_db    => 'test',
   left_tbl   => 'lt',
   right_db   => 'test',
   right_tbl  => 'rt',
   actions    => [ sub {} ],
   replace    => 0,
   queue      => 0,
   tbl_struct => $tbl_struct,
);

is(
   $ch->make_fetch_back_query('1=1'),
   "SELECT `a`, IF(BINARY(`x`)='', '', CONCAT('0x', HEX(`x`))) AS `x`, `b` FROM `test`.`lt` WHERE 1=1 LIMIT 1",
   "Wraps BLOB column in CONCAT('0x', HEX(col)) AS col"
);

$ch = new ChangeHandler(
   Quoter     => $q,
   left_db    => 'test',
   left_tbl   => 'lt',
   right_db   => 'test',
   right_tbl  => 'rt',
   actions    => [ sub {} ],
   replace    => 0,
   queue      => 0,
   hex_blob   => 0,
   tbl_struct => $tbl_struct,
);

is(
   $ch->make_fetch_back_query('1=1'),
   "SELECT `a`, `x`, `b` FROM `test`.`lt` WHERE 1=1 LIMIT 1",
   "Disable blob hexing"
);

# #############################################################################
# Issue 1052: mk-table-sync inserts "0x" instead of "" for empty blob and text
# column values
# #############################################################################
$tbl_struct = {
   cols     => [qw(t)],
   type_for => {t=>'blob'},
};
$ch = new ChangeHandler(
   Quoter     => $q,
   left_db    => 'test',
   left_tbl   => 't',
   right_db   => 'test',
   right_tbl  => 't',
   actions    => [ sub {} ],
   replace    => 0,
   queue      => 0,
   tbl_struct => $tbl_struct,
);

is(
   $ch->make_fetch_back_query('1=1'),
   "SELECT IF(BINARY(`t`)='', '', CONCAT('0x', HEX(`t`))) AS `t` FROM `test`.`t` WHERE 1=1 LIMIT 1",
   "Don't prepend 0x to blank blob/text column value (issue 1052)"
);

# #############################################################################
# An update to the above bug; It should only hexify for blob and binary, not
# for text columns; The latter not only breaks for UTF-8 data, but also
# breaks now that hex-looking columns aren't automatically left unquoted.
# #############################################################################
$tbl_struct = {
   cols     => [qw(t)],
   type_for => {t=>'text'},
};
$ch = new ChangeHandler(
   Quoter     => $q,
   left_db    => 'test',
   left_tbl   => 't',
   right_db   => 'test',
   right_tbl  => 't',
   actions    => [ sub {} ],
   replace    => 0,
   queue      => 0,
   tbl_struct => $tbl_struct,
);

is(
   $ch->make_fetch_back_query('1=1'),
   "SELECT `t` FROM `test`.`t` WHERE 1=1 LIMIT 1",
   "Don't prepend 0x to blank blob/text column value (issue 1052)"
);

# #############################################################################

SKIP: {
   skip 'Cannot connect to sandbox master', 1 unless $master_dbh;
   $sb->load_file('master', "t/lib/samples/issue_641.sql");

   @rows = ();
   $tbl_struct = {
      cols     => [qw(id b)],
      col_posn => {id=>0, b=>1},
      type_for => {id=>'int', b=>'blob'},
   };
   $ch = new ChangeHandler(
      Quoter     => $q,
      left_db    => 'issue_641',
      left_tbl   => 'lt',
      right_db   => 'issue_641',
      right_tbl  => 'rt',
      actions   => [ sub { push @rows, $_[0]; } ],
      replace    => 0,
      queue      => 0,
      tbl_struct => $tbl_struct,
   );
   $ch->fetch_back($master_dbh);

   $ch->change('UPDATE', {id=>1}, [qw(id)] );
   $ch->change('INSERT', {id=>1}, [qw(id)] );

   is_deeply(
      \@rows,
      [
         "UPDATE `issue_641`.`rt` SET `b`=0x089504E470D0A1A0A0000000D4948445200000079000000750802000000E55AD965000000097048597300000EC300000EC301C76FA8640000200049444154789C4CBB7794246779FFBBF78F7B7EBE466177677772CE3D9D667AA67BA62776CE39545557CE3974EE9EB049AB9556392210414258083 WHERE `id`='1' LIMIT 1",
         "INSERT INTO `issue_641`.`rt`(`id`, `b`) VALUES ('1', 0x089504E470D0A1A0A0000000D4948445200000079000000750802000000E55AD965000000097048597300000EC300000EC301C76FA8640000200049444154789C4CBB7794246779FFBBF78F7B7EBE466177677772CE3D9D667AA67BA62776CE39545557CE3974EE9EB049AB9556392210414258083)",
      ],
      "UPDATE and INSERT binary data as hex"
   );
}

# #############################################################################
# Issue 387: More useful comments in mk-table-sync statements
# #############################################################################
@rows = ();
$ch = new ChangeHandler(
   Quoter    => $q,
   right_db  => 'test',  # dst
   right_tbl => 'foo',
   left_db   => 'test',  # src
   left_tbl  => 'test1',
   actions   => [ sub { push @rows, $_[0]; push @dbhs, $_[1]; } ],
   replace   => 0,
   queue     => 1,
);

$ch->change('INSERT', { a => 1, b => 2 }, [qw(a)] );
$ch->process_rows(1, "trace");

is_deeply(
   \@rows,
   ["INSERT INTO `test`.`foo`(`a`, `b`) VALUES ('1', '2') /*percona-toolkit trace*/",],
   "process_rows() appends trace msg to SQL statements"
);

# #############################################################################
# ChangeHandler doesn't quote varchar columns with hex-looking values
# https://bugs.launchpad.net/percona-toolkit/+bug/1038276
# #############################################################################
SKIP: {
   skip 'Cannot connect to sandbox master', 1 unless $master_dbh;
   $sb->load_file('master', "t/lib/samples/bug_1038276.sql");

   @rows = ();
   $tbl_struct = {
      cols      => [qw(id b)],
      col_posn  => {id=>0, b=>1},
      type_for  => {id=>'int', b=>'varchar'},
   };
   $ch = new ChangeHandler(
      Quoter     => $q,
      left_db    => 'bug_1038276',
      left_tbl   => 'lt',
      right_db   => 'bug_1038276',
      right_tbl  => 'rt',
      actions   => [ sub { push @rows, $_[0]; } ],
      replace    => 0,
      queue      => 0,
      tbl_struct => $tbl_struct,
   );
   $ch->fetch_back($master_dbh);

   $ch->change('UPDATE', {id=>1}, [qw(id)] );
   $ch->change('INSERT', {id=>1}, [qw(id)] );

   is_deeply(
      \@rows,
      [
         "UPDATE `bug_1038276`.`rt` SET `b`='0x89504E470D0A1A0A0000000D4948445200000079000000750802000000E55AD965000000097048597300000EC300000EC301C76FA8640000200049444154789C4CBB7794246779FFBBF78F7B7EBE466177677772CE3D9D667AA67BA62776CE39545557CE3974EE9EB049AB9556392210414258083' WHERE `id`='1' LIMIT 1",
         "INSERT INTO `bug_1038276`.`rt`(`id`, `b`) VALUES ('1', '0x89504E470D0A1A0A0000000D4948445200000079000000750802000000E55AD965000000097048597300000EC300000EC301C76FA8640000200049444154789C4CBB7794246779FFBBF78F7B7EBE466177677772CE3D9D667AA67BA62776CE39545557CE3974EE9EB049AB9556392210414258083')",
      ],
      "UPDATE and INSERT quote data regardless of how it looks if tbl_struct->quote_val is true"
   );
}

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave1_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;
   