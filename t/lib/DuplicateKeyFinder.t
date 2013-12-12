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

use VersionParser;
use DuplicateKeyFinder;
use Quoter;
use TableParser;
use PerconaTest;

my $dk = new DuplicateKeyFinder();
my $q  = new Quoter();
my $tp = new TableParser(Quoter => $q);

my $sample = "t/lib/samples/dupekeys/";
my $dupes;
my $callback = sub {
   push @$dupes, $_[0];
};

my $opt = { mysql_version => VersionParser->new('4.1.0') };
my $ddl;
my $tbl;

isa_ok($dk, 'DuplicateKeyFinder');

$ddl   = load_file('t/lib/samples/one_key.sql');
$dupes = [];
my ($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [
   ],
   'One key, no dupes'
);

$ddl   = load_file('t/lib/samples/dupe_key.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'          => 'a',
         'cols'         => [qw(a)],
         ddl            => 'KEY `a` (`a`),',
         'duplicate_of' => 'a_2',
         'duplicate_of_cols' => [qw(a b)],
         duplicate_of_ddl    => 'KEY `a_2` (`a`,`b`)',
         'reason'       => 'a is a left-prefix of a_2',
         dupe_type      => 'prefix',
      }
   ],
   'Two dupe keys on table dupe_key'
);

$ddl   = load_file('t/lib/samples/dupe_key_reversed.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'          => 'a',
         'cols'         => [qw(a)],
         ddl            => 'KEY `a` (`a`),',
         'duplicate_of' => 'a_2',
         'duplicate_of_cols' => [qw(a b)],
         duplicate_of_ddl    => 'KEY `a_2` (`a`,`b`),',
         'reason'       => 'a is a left-prefix of a_2',
         dupe_type      => 'prefix',
      }
   ],
   'Two dupe keys on table dupe_key in reverse'
);

# This test might fail if your system sorts a_3 before a_2, because the
# keys are sorted by columns, not name. If this happens, then a_3 will
# duplicate a_2.
$ddl   = load_file('t/lib/samples/dupe_keys_thrice.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'          => 'a_3',
         'cols'         => [qw(a b)],
         ddl            => 'KEY `a_3` (`a`,`b`)',
         'duplicate_of' => 'a_2',
         'duplicate_of_cols' => [qw(a b)],
         duplicate_of_ddl    => 'KEY `a_2` (`a`,`b`),',
         'reason'       => 'a_3 is a duplicate of a_2',
         dupe_type      => 'exact',
      },
      {
         'key'          => 'a',
         'cols'         => [qw(a)],
         ddl            => 'KEY `a` (`a`),',
         'duplicate_of' => 'a_2',
         'duplicate_of_cols' => [qw(a b)],
         duplicate_of_ddl    => 'KEY `a_2` (`a`,`b`),',
         'reason'       => 'a is a left-prefix of a_2',
         dupe_type      => 'prefix',
      },
   ],
   'Dupe keys only output once (may fail due to different sort order)'
);

$ddl   = load_file('t/lib/samples/nondupe_fulltext.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [],
   'No dupe keys b/c of fulltext'
);
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   ignore_structure => 1,
   callback         => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'          => 'a',
         'cols'         => [qw(a)],
         ddl            => 'KEY `a` (`a`),',
         'duplicate_of' => 'a_2',
         'duplicate_of_cols' => [qw(a b)],
         duplicate_of_ddl    => 'FULLTEXT KEY `a_2` (`a`,`b`),',
         'reason'       => 'a is a left-prefix of a_2',
         dupe_type      => 'prefix',
      },
   ],
   'Dupe keys when ignoring structure'
);

$ddl   = load_file('t/lib/samples/nondupe_fulltext_not_exact.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [],
   'No dupe keys b/c fulltext requires exact match (issue 10)'
);

$ddl   = load_file('t/lib/samples/dupe_fulltext_exact.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'          => 'ft_idx_a_b_2',
         'cols'         => [qw(a b)],
         ddl            => 'FULLTEXT KEY `ft_idx_a_b_2` (`a`,`b`)',
         'duplicate_of' => 'ft_idx_a_b_1',
         'duplicate_of_cols' => [qw(a b)],
         duplicate_of_ddl    => 'FULLTEXT KEY `ft_idx_a_b_1` (`a`,`b`),',
         'reason'       => 'ft_idx_a_b_2 is a duplicate of ft_idx_a_b_1',
         dupe_type      => 'exact',
      }
   ],
   'Dupe exact fulltext keys (issue 10)'
);

$ddl   = load_file('t/lib/samples/dupe_fulltext_reverse_order.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'          => 'ft_idx_a_b',
         'cols'         => [qw(a b)],
         ddl            => 'FULLTEXT KEY `ft_idx_a_b` (`a`,`b`),',
         'duplicate_of' => 'ft_idx_b_a',
         'duplicate_of_cols' => [qw(b a)],
         duplicate_of_ddl    => 'FULLTEXT KEY `ft_idx_b_a` (`b`,`a`)',
         'reason'       => 'ft_idx_a_b is a duplicate of ft_idx_b_a',
         dupe_type      => 'exact',
      }
   ],
   'Dupe reverse order fulltext keys (issue 10)'
);

$ddl   = load_file('t/lib/samples/dupe_key_unordered.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [],
   'No dupe keys because of order'
);
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   ignore_order => 1,
   callback     => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'          => 'a',
         'cols'         => [qw(b a)],
         ddl            => 'KEY `a` (`b`,`a`),',
         'duplicate_of' => 'a_2',
         'duplicate_of_cols' => [qw(a b)],
         duplicate_of_ddl    => 'KEY `a_2` (`a`,`b`),',
         'reason'       => 'a is a duplicate of a_2',
         dupe_type      => 'exact',
      }
   ],
   'Two dupe keys when ignoring order'
);

# #############################################################################
# Clustered key tests.
# #############################################################################
$ddl   = load_file('t/lib/samples/innodb_dupe.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);

is_deeply(
   $dupes,
   [],
   'No duplicate keys with ordinary options'
);
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   clustered => 1,
   tbl_info  => { engine => 'InnoDB', ddl => $ddl },
   callback  => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'          => 'b',
         'cols'         => [qw(b a)],
         ddl            => 'KEY `b` (`b`,`a`)',
         'duplicate_of' => 'PRIMARY',
         'duplicate_of_cols' => [qw(a)],
         duplicate_of_ddl    => 'PRIMARY KEY  (`a`),',
         'reason'       => 'Key b ends with a prefix of the clustered index',
         dupe_type      => 'clustered',
         short_key      => '`b`',
      }
   ],
   'Duplicate keys with cluster option'
);

$ddl = load_file('t/lib/samples/dupe_if_it_were_innodb.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   clustered => 1,
   tbl_info  => {engine    => 'MyISAM', ddl => $ddl},
   callback  => $callback);
is_deeply(
   $dupes,
   [],
   'No cluster-duplicate keys because not InnoDB'
);

# This table is a test case for an infinite loop I ran into while writing the
# cluster stuff
$ddl = load_file('t/lib/samples/mysql_db.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   clustered => 1,
   tbl_info  => { engine    => 'InnoDB', ddl => $ddl },
   callback  => $callback);
is_deeply(
   $dupes,
   [],
   'No cluster-duplicate keys in mysql.db'
);

# #############################################################################
# Duplicate FOREIGN KEY tests.
# #############################################################################
$ddl   = load_file('t/lib/samples/dupe_fk_one.sql');
$dupes = [];
$dk->get_duplicate_fks(
   $tp->get_fks($ddl, {database => 'test'}),
   callback => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'               => 't1_ibfk_1',
         'cols'              => [qw(a b)],
         ddl                 => 'CONSTRAINT `t1_ibfk_1` FOREIGN KEY (`a`, `b`) REFERENCES `t2` (`a`, `b`)',
         'duplicate_of'      => 't1_ibfk_2',
         'duplicate_of_cols' => [qw(b a)],
         duplicate_of_ddl    => 'CONSTRAINT `t1_ibfk_2` FOREIGN KEY (`b`, `a`) REFERENCES `t2` (`b`, `a`)',
         'reason'            => 'FOREIGN KEY t1_ibfk_1 (`a`, `b`) REFERENCES `test`.`t2` (`a`, `b`) is a duplicate of FOREIGN KEY t1_ibfk_2 (`b`, `a`) REFERENCES `test`.`t2` (`b`, `a`)',
         dupe_type      => 'fk',
      }
   ],
   'Two duplicate foreign keys'
);

$ddl   = load_file('t/lib/samples/sakila_film.sql');
$dupes = [];
$dk->get_duplicate_fks(
   $tp->get_fks($ddl, {database => 'sakila'}),
   callback => $callback);
is_deeply(
   $dupes,
   [],
   'No duplicate foreign keys in sakila_film.sql'
);

# #############################################################################
# Issue 9: mk-duplicate-key-checker should treat unique and FK indexes specially
# #############################################################################

$ddl   = load_file('t/lib/samples/issue_9-1.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [],
   'Unique and non-unique keys with common prefix not dupes (issue 9)'
);

$ddl   = load_file('t/lib/samples/issue_9-2.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [],
   'PRIMARY and non-unique keys with common prefix not dupes (issue 9)'
);

$ddl   = load_file('t/lib/samples/issue_9-3.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'          => 'j',
         'cols'         => [qw(a b)],
         ddl            => 'KEY `j` (`a`,`b`)',
         'duplicate_of' => 'i',
         'duplicate_of_cols' => [qw(a b)],
         duplicate_of_ddl    => 'UNIQUE KEY `i` (`a`,`b`),',
         'reason'       => 'j is a duplicate of i',
         dupe_type      => 'exact',
      }
   ],
   'Non-unique key dupes unique key with same col cover (issue 9)'
);

$ddl   = load_file('t/lib/samples/issue_9-4.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'          => 'j',
         'cols'         => [qw(a b)],
         ddl            => 'KEY `j` (`a`,`b`)',
         'duplicate_of' => 'PRIMARY',
         'duplicate_of_cols' => [qw(a b)],
         duplicate_of_ddl    => 'PRIMARY KEY  (`a`,`b`),',
         'reason'       => 'j is a duplicate of PRIMARY',
         dupe_type      => 'exact',
      }
   ],
   'Non-unique key dupes PRIMARY key same col cover (issue 9)'
);

$ddl   = load_file('t/lib/samples/issue_9-5.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [],
   'Two unique keys with common prefix are not dupes'
);

$ddl   = load_file('t/lib/samples/uppercase_names.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'               => 'A',
         'cols'              => [qw(A)],
         ddl                 => 'KEY `A` (`A`)',
         'duplicate_of'      => 'PRIMARY',
         'duplicate_of_cols' => [qw(A)],
         duplicate_of_ddl    => 'PRIMARY KEY  (`A`),',
         'reason'            => "A is a duplicate of PRIMARY",
         dupe_type      => 'exact',
      },
   ],
   'Finds duplicates OK on uppercase columns',
);

$ddl   = load_file('t/lib/samples/issue_9-7.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'               => 'ua_b',
         'cols'              => [qw(a b)],
         ddl                 => 'UNIQUE KEY `ua_b` (`a`,`b`),',
         'duplicate_of'      => 'a_b_c',
         'duplicate_of_cols' => [qw(a b c)],
         duplicate_of_ddl    => 'KEY `a_b_c` (`a`,`b`,`c`)',
         'reason'            => "Uniqueness of ua_b ignored because PRIMARY is a stronger constraint\nua_b is a left-prefix of a_b_c",
         dupe_type      => 'prefix',
      },
   ],
   'Redundantly unique key dupes normal key after unconstraining'
);

$ddl   = load_file('t/lib/samples/issue_9-6.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [
      {
       'duplicate_of' => 'PRIMARY',
       'reason' => 'a is a left-prefix of PRIMARY',
       dupe_type      => 'prefix',
       'duplicate_of_cols' => [qw(a b)],
       duplicate_of_ddl    => 'PRIMARY KEY  (`a`,`b`),',
       'cols' => [qw(a)],
       'key'  => 'a',
       ddl    => 'KEY `a` (`a`),',
      },
      {
       'duplicate_of' => 'PRIMARY',
       'reason' => 'a_b is a duplicate of PRIMARY',
       dupe_type      => 'exact',
       'duplicate_of_cols' => [qw(a b)],
       duplicate_of_ddl    => 'PRIMARY KEY  (`a`,`b`),',
       'cols' => [qw(a b)],
       'key'  => 'a_b',
       ddl    => 'KEY `a_b` (`a`,`b`),',
      },
      {
       'duplicate_of' => 'PRIMARY',
       'reason' => "Uniqueness of ua_b ignored because ua is a stronger constraint\nua_b is a duplicate of PRIMARY",
       dupe_type      => 'exact',
       'duplicate_of_cols' => [qw(a b)],
       duplicate_of_ddl    => 'PRIMARY KEY  (`a`,`b`),',
       'cols' => [qw(a b)],
       'key'  => 'ua_b',
       ddl    => 'UNIQUE KEY `ua_b` (`a`,`b`),',
      },
      {
       'duplicate_of' => 'PRIMARY',
       'reason' => "Uniqueness of ua_b2 ignored because ua is a stronger constraint\nua_b2 is a duplicate of PRIMARY",
       dupe_type      => 'exact',
       'duplicate_of_cols' => [qw(a b)],
       duplicate_of_ddl    => 'PRIMARY KEY  (`a`,`b`),',
       'cols' => [qw(a b)],
       'key'  => 'ua_b2',
       ddl    => 'UNIQUE KEY `ua_b2` (`a`,`b`),',
      }
   ],
   'Very pathological case',
);

# #############################################################################
# Issue 269: mk-duplicate-key-checker: Wrongly suggesting removing index
# #############################################################################
$ddl   = load_file('t/lib/samples/issue_269-1.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [
   ],
   'Keep stronger unique constraint that is prefix'
);

# #############################################################################
# Issue 331: mk-duplicate-key-checker crashes when printing column types
# #############################################################################
$ddl   = load_file('t/lib/samples/issue_331.sql');
$dupes = [];
$dk->get_duplicate_fks(
   $tp->get_fks($ddl, {database => 'test'}),
   callback => $callback);
is_deeply(
   $dupes,
   [
      {
         'key'               => 'fk_1',
         'cols'              => [qw(id)],
         ddl                 => 'CONSTRAINT `fk_1` FOREIGN KEY (`id`) REFERENCES `issue_331_t1` (`t1_id`)',
         'duplicate_of'      => 'fk_2',
         'duplicate_of_cols' => [qw(id)],
         duplicate_of_ddl    => 'CONSTRAINT `fk_2` FOREIGN KEY (`id`) REFERENCES `issue_331_t1` (`t1_id`)',
         'reason'            => 'FOREIGN KEY fk_1 (`id`) REFERENCES `test`.`issue_331_t1` (`t1_id`) is a duplicate of FOREIGN KEY fk_2 (`id`) REFERENCES `test`.`issue_331_t1` (`t1_id`)',
         dupe_type      => 'fk',
      }
   ],
   'fk col not in referencing table (issue 331)'
);

# #############################################################################
# Issue 295: Enhance rules for clustered keys in mk-duplicate-key-checker
# #############################################################################
is(
   $dk->shorten_clustered_duplicate('`a`', '`b`,`a`'),
   '`b`',
   "shorten_clustered_duplicate('`a`', '`b`,`a`')"
);

is(
   $dk->shorten_clustered_duplicate('`a`', '`a`'),
   '`a`',
   "shorten_clustered_duplicate('`a`', '`a`')"
);

is(
   $dk->shorten_clustered_duplicate('`a`,`b`', '`c`,`a`,`b`'),
   '`c`',
   "shorten_clustered_duplicate('`a`,`b`', '`c`,`a`,`b`'),"
);

$ddl   = load_file('t/lib/samples/issue_295-1.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   callback => $callback);
is_deeply(
   $dupes,
   [],
   'Do not remove clustered key acting as primary key'
);

# #############################################################################
# Issue 904: Tables that confuse mk-duplicate-key-checker
# #############################################################################
$ddl   = load_file("$sample/issue-904-1.txt");
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   clustered     => 1,
   tbl_info      => { engine => 'InnoDB', ddl => $ddl },
   callback      => $callback
);

is_deeply(
   $dupes,
   [],
   'Clustered key with multiple columns (issue 904 1)'
);

$ddl   = load_file("$sample/issue-904-2.txt");
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   clustered     => 1,
   tbl_info      => { engine => 'InnoDB', ddl => $ddl },
   callback      => $callback
);

is_deeply(
   $dupes,
   [],
   'Clustered key with multiple columns (issue 904 2)'
);

# #############################################################################
# Issue 1004: mk-dupe-key-checker recommends dropping and re-adding same index
# #############################################################################
$ddl   = load_file("$sample/issue-1004.txt");
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   clustered     => 1,
   tbl_info      => { engine => 'InnoDB', ddl => $ddl },
   callback      => $callback
);

is_deeply(
   $dupes,
   [],
   'Issue 1004'
);

# #############################################################################
# Issue 1192: DROP/ADD leaves structure unchanged
# #############################################################################
$ddl   = load_file("$sample/issue-1192.sql");
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   clustered     => 1,
   tbl_info      => { engine => 'InnoDB', ddl => $ddl },
   callback      => $callback
);

is_deeply(
   $dupes,
   [{
      key               => 'a',
      cols              => ['a'],
      ddl               => 'KEY `a` (`a`),',
      reason            => 'a is a duplicate of PRIMARY',
      dupe_type         => 'exact',
      duplicate_of      => 'PRIMARY',
      duplicate_of_cols => ['a'],
      duplicate_of_ddl  => 'PRIMARY KEY (`a`),',
   }],
   'Issue 1192'
);


# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/894140
# #############################################################################
$ddl   = load_file('t/lib/samples/dupekeys/dupe-cluster-bug-894140.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   clustered     => 1,
   callback      => $callback,
   tbl_info      => { engine => 'InnoDB', ddl => $ddl },
);

is_deeply(
   $dupes,
   [
     {
       cols              => [ 'row_id' ],
       ddl               => 'UNIQUE KEY `row_id` (`row_id`),',
       dupe_type         => 'exact',
       duplicate_of      => 'PRIMARY',
       duplicate_of_cols => [ 'row_id' ],
       duplicate_of_ddl  => 'PRIMARY KEY (`row_id`),',
       key               => 'row_id',
       reason            => "Uniqueness of row_id ignored because PRIMARY is a duplicate constraint\nrow_id is a duplicate of PRIMARY",
     },
     {
       cols              => [ 'player_id' ],
       ddl               => 'KEY `player_id_2` (`player_id`)',
       dupe_type         => 'exact',
       duplicate_of      => 'player_id',
       duplicate_of_cols => [ 'player_id' ],
       duplicate_of_ddl  => 'UNIQUE KEY `player_id` (`player_id`),',
       key               => 'player_id_2',
       reason            => 'player_id_2 is a duplicate of player_id',
     },
   ],
   'Finds duplicates OK on uppercase columns',
);

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1214114
# #############################################################################
#$ddl   = load_file('t/lib/samples/dupekeys/prefix_bug_1214114.sql');
#$dupes = [];
#($keys, $ck) = $tp->get_keys($ddl, $opt);
#$dk->get_duplicate_keys(
#   $keys,
#   clustered_key => $ck,
#   clustered     => 1,
#   callback      => $callback,
#   tbl_info      => { engine => 'InnoDB', ddl => $ddl },
#);
#
#is_deeply(
#   $dupes,
#   [{
#      cols => ['b', 'id'],
#      ddl => 'KEY `b` (`b`,`id`)',
#      dupe_type => 'clustered',
#      duplicate_of => 'PRIMARY',
#      duplicate_of_cols => ['id'],
#      duplicate_of_ddl => 'PRIMARY KEY (`id`),',
#      key => 'b',
#      reason => 'Key b ends with a prefix of the clustered index',
#      short_key => '`b`',
#   }],
#   "Prefix bug 1214114"
#) or diag(Dumper($dupes));

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1217013
 #############################################################################
$ddl   = load_file('t/lib/samples/dupekeys/simple_dupe_bug_1217013.sql');
$dupes = [];
($keys, $ck) = $tp->get_keys($ddl, $opt);
$dk->get_duplicate_keys(
   $keys,
   clustered_key => $ck,
   clustered     => 1,
   callback      => $callback,
   tbl_info      => { engine => 'InnoDB', ddl => $ddl },
);

is_deeply(
   $dupes,
   [{
      cols              => ['domain'],
      ddl               => 'UNIQUE KEY `domain` (`domain`),',
      dupe_type         => 'exact',
      duplicate_of      => 'unique_key_domain',
      duplicate_of_cols => ['domain'],
      duplicate_of_ddl  => 'UNIQUE KEY `unique_key_domain` (`domain`)',
      key               => 'domain',
      reason            => "Uniqueness of domain ignored because unique_key_domain is a duplicate constraint\ndomain is a duplicate of unique_key_domain",
   }],
   "Exact dupe uniques (bug 1217013)"
) or diag(Dumper($dupes));

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $dk->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
done_testing;
