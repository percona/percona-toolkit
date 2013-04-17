#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';

use Test::More tests => 137;
use English qw(-no_match_vars);

use PerconaTest;
use SQLParser;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $sp = new SQLParser();

# ############################################################################
# Should throw some errors for stuff it can't do.
# ############################################################################
throws_ok(
   sub { $sp->parse('drop table foo'); },
   qr/Cannot parse DROP queries/,
   "Dies if statement type cannot be parsed"
);

# ############################################################################
# parse_csv
# ############################################################################
sub test_parse_csv {
   my ( $in, $expect, %args ) = @_;
   my $got = $sp->_parse_csv($in, %args);
   is_deeply(
      $got,
      $expect,
      "parse_csv($in)"
   ) or print Dumper($got);
   return;
}

test_parse_csv(
   "a,b",
   [qw(a b)],
);

test_parse_csv(
   q{'', ','},
   [q{''}, q{','}],
   quoted_values => 1,
);

test_parse_csv(
   q{"", "a"},
   [q{""}, q{"a"}],
   quoted_values => 1,
);

test_parse_csv(
   q{'hello, world!','hi'},
   [q{'hello, world!'}, q{'hi'}],
   quoted_values => 1,
);

test_parse_csv(
   q{'a',   "b",   c},
   [q{'a'}, q{"b"}, q{c}],
   quoted_values => 1,
);

test_parse_csv(
   q{"x, y", "", a, 'b'},
   [q{"x, y"}, q{""}, q{a}, q{'b'}],
   quoted_values => 1,
);

# ############################################################################
# is_identifier
# ############################################################################
sub test_is_identifier {
   my ( $thing, $expect ) = @_;
   is(
      $sp->is_identifier($thing),
      $expect,
      "$thing is" . ($expect ? "" : " not") . " an ident"
   );
   return;
}

test_is_identifier("tbl",        1);
test_is_identifier("`tbl`",      1);
test_is_identifier("'tbl'",      0);
test_is_identifier("\"tbl\"",    0);
test_is_identifier('db.tbl',     1);
test_is_identifier('"db.tbl"',   0);
test_is_identifier('db.tbl.col', 1);
test_is_identifier('1',          0);

# #############################################################################
# WHERE where_condition
# #############################################################################
sub test_where {
   my ( $where, $struct ) = @_;
   is_deeply(
      $sp->parse_where($where),
      $struct,
      "WHERE " . substr($where, 0, 60) 
         . (length $where > 60 ? '...' : ''),
   );
};

test_where(
   'i=1',
   [
      {
         predicate => undef,
         left_arg  => 'i',
         operator  => '=',
         right_arg => '1',
      },
   ],
);

test_where(
   'i=1 or j<10 or k>100 or l != 0',
   [
      {
         predicate => undef,
         left_arg  => 'i',
         operator  => '=',
         right_arg => '1',
      },
      {
         predicate => 'or',
         left_arg  => 'j',
         operator  => '<',
         right_arg => '10',
      },
      {
         predicate => 'or',
         left_arg  => 'k',
         operator  => '>',
         right_arg => '100',
      },
      {
         predicate => 'or',
         left_arg  => 'l',
         operator  => '!=',
         right_arg => '0',
      },
   ],
);

test_where(
   'i=1 and foo="bar"',
   [
      {
         predicate => undef,
         left_arg  => 'i',
         operator  => '=',
         right_arg => '1',
      },
      {
         predicate => 'and',
         left_arg  => 'foo',
         operator  => '=',
         right_arg => '"bar"',
      },
   ],
);

test_where(
   '(i=1 and foo="bar")',
   [
      {
         predicate => undef,
         left_arg  => 'i',
         operator  => '=',
         right_arg => '1',
      },
      {
         predicate => 'and',
         left_arg  => 'foo',
         operator  => '=',
         right_arg => '"bar"',
      },
   ],
);

test_where(
   '(i=1) and (foo="bar")',
   [
      {
         predicate => undef,
         left_arg  => 'i',
         operator  => '=',
         right_arg => '1',
      },
      {
         predicate => 'and',
         left_arg  => 'foo',
         operator  => '=',
         right_arg => '"bar"',
      },
   ],
);

test_where(
   'i= 1 and foo ="bar" or j = 2',
   [
      {
         predicate => undef,
         left_arg  => 'i',
         operator  => '=',
         right_arg => '1',
      },
      {
         predicate => 'and',
         left_arg  => 'foo',
         operator  => '=',
         right_arg => '"bar"',
      },
      {
         predicate => 'or',
         left_arg  => 'j',
         operator  => '=',
         right_arg => '2',
      },
   ],
);

test_where(
   'i=1 and foo="i have spaces and a keyword!"',
   [
      {
         predicate => undef,
         left_arg  => 'i',
         operator  => '=',
         right_arg => '1',
      },
      {
         predicate => 'and',
         left_arg  => 'foo',
         operator  => '=',
         right_arg => '"i have spaces and a keyword!"',
      },
   ],
);

test_where(
   'i="this and this" or j<>"that and that" and k="and or and" and z=1',
   [
      {
         predicate => undef,
         left_arg  => 'i',
         operator  => '=',
         right_arg => '"this and this"',
      },
      {
         predicate => 'or',
         left_arg  => 'j',
         operator  => '<>',
         right_arg => '"that and that"',
      },
      {
         predicate => 'and',
         left_arg  => 'k',
         operator  => '=',
         right_arg => '"and or and"',
      },
      {
         predicate => 'and',
         left_arg  => 'z',
         operator  => '=',
         right_arg => '1',
      },
   ],
);

test_where(
   'i="this and this" or j in ("and", "or") and x is not null or a between 1 and 10 and sz="the keyword \'and\' is in the middle or elsewhere hidden"',
   [
      {
         predicate => undef,
         left_arg  => 'i',
         operator  => '=',
         right_arg => '"this and this"',
      },
      {
         predicate => 'or',
         left_arg  => 'j',
         operator  => 'in',
         right_arg => '("and", "or")',
      },
      {
         predicate => 'and',
         left_arg  => 'x',
         operator  => 'is not',
         right_arg => 'null',
      },
      {
         predicate => 'or',
         left_arg  => 'a',
         operator  => 'between',
         right_arg => '1 and 10',
      },
      {
         predicate => 'and',
         left_arg  => 'sz',
         operator  => '=',
         right_arg => '"the keyword \'and\' is in the middle or elsewhere hidden"',
      },
   ],
);

test_where(
   "(`ga_announcement`.`disabled` = 0)",
   [
      {
         predicate => undef,
         left_arg  => '`ga_announcement`.`disabled`',
         operator  => '=',
         right_arg => '0',
      },
   ]
);

test_where(
   "1",
   [
      {
         predicate => undef,
         left_arg  => undef,
         operator  => undef,
         right_arg => '1',
      },
   ]
);

test_where(
   "1 and foo not like '%bar%'",
   [
      {
         predicate => undef,
         left_arg  => undef,
         operator  => undef,
         right_arg => '1',
      },
      {
         predicate => 'and',
         left_arg  => 'foo',
         operator  => 'not like',
         right_arg => '\'%bar%\'',
      },
   ]
);

test_where(
   "TRUE or FALSE",
   [
      {
         predicate => undef,
         left_arg  => undef,
         operator  => undef,
         right_arg => 'true',
      },
      {
         predicate => 'or',
         left_arg  => undef,
         operator  => undef,
         right_arg => 'false',
      },
   ]
);

test_where(
   "TO_DAYS(column) < TO_DAYS(NOW()) - 5",
   [
      {
         predicate => undef,
         left_arg  => "TO_DAYS(column)",
         operator  => '<',
         right_arg => 'TO_DAYS(NOW()) - 5',
      },
   ]
);

test_where(
   "id <> CONV(ff, 16, 10)",
   [
      {
         predicate => undef,
         left_arg  => 'id',
         operator  => '<>',
         right_arg => 'CONV(ff, 16, 10)',
      },
   ]
);

test_where(
   "edpik.input_key = input_key.id",
   [
      {
         predicate => undef,
         left_arg  => 'edpik.input_key',
         operator  => '=',
         right_arg => 'input_key.id'
      },
   ]
);

test_where(
   "((`sakila`.`city`.`country_id` = `sakila`.`country`.`country_id`) and (`sakila`.`country`.`country` = 'Brazil') and (`sakila`.`city`.`city` like 'A%'))",
   [
      {
         predicate => undef,
         left_arg  => '`sakila`.`city`.`country_id`',
         operator  => '=',
         right_arg => '`sakila`.`country`.`country_id`'
      },
      {
        predicate => 'and',
        left_arg  => '`sakila`.`country`.`country`',
        operator  => '=',
        right_arg => '\'Brazil\''
      },
      {
        predicate => 'and',
        left_arg  => '`sakila`.`city`.`city`',
        operator  => 'like',
        right_arg => '\'A%\''
      }
   ]
);

# #############################################################################
# Whitespace and comments.
# #############################################################################
is(
   $sp->clean_query(' /* leading comment */select *
      from tbl where /* comment */ id=1  /*trailing comment*/ '
   ),
   'select * from tbl where  id=1',
   'Remove extra whitespace and comment blocks'
);

is(
   $sp->clean_query('/*
      leading comment
      on multiple lines
*/ select * from tbl where /* another
silly comment */ id=1
/*trailing comment
also on mutiple lines*/ '
   ),
   'select * from tbl where  id=1',
   'Remove multi-line comment blocks'
);

is(
   $sp->clean_query('-- SQL style      
   -- comments
   --

  
select now()
'
   ),
   'select now()',
   'Remove multiple -- comment lines and blank lines'
);


# #############################################################################
# Normalize space around certain SQL keywords.  (This makes parsing easier.)
# #############################################################################
is(
   $sp->normalize_keyword_spaces('insert into t value(1)'),
   'insert into t value (1)',
   'Add space VALUE (cols)'
);

is(
   $sp->normalize_keyword_spaces('insert into t values(1)'),
   'insert into t values (1)',
   'Add space VALUES (cols)'
);

is(
   $sp->normalize_keyword_spaces('select * from a join b on(foo)'),
   'select * from a join b on (foo)',
   'Add space ON (conditions)'
);

is(
   $sp->normalize_keyword_spaces('select * from a join b on(foo) join c on(bar)'),
   'select * from a join b on (foo) join c on (bar)',
   'Add space multiple ON (conditions)'
);

is(
   $sp->normalize_keyword_spaces('select * from a join b using(foo)'),
   'select * from a join b using (foo)',
   'Add space using (conditions)'
);

is(
   $sp->normalize_keyword_spaces('select * from a join b using(foo) join c using(bar)'),
   'select * from a join b using (foo) join c using (bar)',
   'Add space multiple USING (conditions)'
);

is(
   $sp->normalize_keyword_spaces('select * from a join b using(foo) join c on(bar)'),
   'select * from a join b using (foo) join c on (bar)',
   'Add space USING and ON'
);

# ###########################################################################
# GROUP BY
# ###########################################################################
is_deeply(
   $sp->parse_group_by('col, tbl.bar, 4, col2 ASC, MIN(bar)'),
   [
      { column => 'col', },
      { table => 'tbl', column => 'bar', },
      { position => '4', },
      { column => 'col2', sort => 'ASC', },
      { function => 'MIN', expression => 'bar' },
   ],
   "GROUP BY col, tbl.bar, 4, col2 ASC, MIN(bar)"
);

# ###########################################################################
# ORDER BY
# ###########################################################################
is_deeply(
   $sp->parse_order_by('foo'),
   [{column=>'foo'}],
   'ORDER BY foo'
);
is_deeply(
   $sp->parse_order_by('foo'),
   [{column=>'foo'}],
   'order by foo'
);
is_deeply(
   $sp->parse_order_by('foo, bar'),
   [
      {column => 'foo'},
      {column => 'bar'},
   ],
   'order by foo, bar'
);
is_deeply(
   $sp->parse_order_by('foo asc, bar'),
   [
      {column => 'foo', sort => 'ASC'},
      {column => 'bar'},
   ],
   'order by foo asc, bar'
);
is_deeply(
   $sp->parse_order_by('1'),
   [{position => '1'}],
   'ORDER BY 1'
);
is_deeply(
   $sp->parse_order_by('RAND()'),
   [{function => 'RAND'}],
   'ORDER BY RAND()'
);

# ###########################################################################
# LIMIT
# ###########################################################################
is_deeply(
   $sp->parse_limit('1'),
   { row_count => 1, },
   'LIMIT 1'
);
is_deeply(
   $sp->parse_limit('1, 2'),
   { row_count => 2,
     offset    => 1,
   },
   'LIMIT 1, 2'
);
is_deeply(
   $sp->parse_limit('5 OFFSET 10'),
   { row_count       => 5,
     offset          => 10,
     explicit_offset => 1,
   },
   'LIMIT 5 OFFSET 10'
);


# ###########################################################################
# FROM table_references
# ###########################################################################

sub test_from {
   my ( $from, $struct ) = @_;
   my $got = $sp->parse_from($from);
   is_deeply(
      $got,
      $struct,
      "FROM $from"
   ) or print Dumper($got);
};

test_from(
   'tbl',
   [ { tbl => 'tbl', } ],
);

test_from(
   'tbl ta',
   [ { tbl  => 'tbl', alias => 'ta', }  ],
);

test_from(
   'tbl AS ta',
   [ { tbl           => 'tbl',
       alias          => 'ta',
       explicit_alias => 1,
   } ],
);

test_from(
   't1, t2',
   [
      { tbl => 't1', },
      {
         tbl => 't2',
         join => {
            to    => 't1',
            type  => 'inner',
            ansi  => 0,
         },
      }
   ],
);

test_from(
   't1 a, t2 as b',
   [
      { tbl  => 't1',
        alias => 'a',
      },
      {
        tbl           => 't2',
        alias          => 'b',
        explicit_alias => 1,
        join           => {
            to   => 't1',
            type => 'inner',
            ansi => 0,
         },
      }
   ],
);


test_from(
   't1 JOIN t2 ON t1.id=t2.id',
   [
      {
         tbl => 't1',
      },
      {
         tbl => 't2',
         join => {
            to         => 't1',
            type       => 'inner',
            condition  => 'on',
            where      => [
               {
                  predicate => undef,
                  left_arg  => 't1.id',
                  operator  => '=',
                  right_arg => 't2.id',
               },
            ],
            ansi       => 1,
         },
      }
   ],
);

test_from(
   't1 a JOIN t2 as b USING (id)',
   [
      {
         tbl  => 't1',
         alias => 'a',
      },
      {
         tbl  => 't2',
         alias => 'b',
         explicit_alias => 1,
         join  => {
            to         => 't1',
            type       => 'inner',
            condition  => 'using',
            columns    => ['id'],
            ansi       => 1,
         },
      },
   ],
);

test_from(
   't1 JOIN t2 ON t1.id=t2.id JOIN t3 ON t1.id=t3.id',
   [
      {
         tbl  => 't1',
      },
      {
         tbl  => 't2',
         join  => {
            to         => 't1',
            type       => 'inner',
            condition  => 'on',
            where      => [
               {
                  predicate => undef,
                  left_arg  => 't1.id',
                  operator  => '=',
                  right_arg => 't2.id',
               },
            ],
            ansi       => 1,
         },
      },
      {
         tbl  => 't3',
         join  => {
            to         => 't2',
            type       => 'inner',
            condition  => 'on',
            where      => [
               {
                  predicate => undef,
                  left_arg  => 't1.id',
                  operator  => '=',
                  right_arg => 't3.id',
               },
            ],
            ansi       => 1,
         },
      },
   ],
);

test_from(
   't1 AS a LEFT JOIN t2 b ON a.id = b.id',
   [
      {
         tbl  => 't1',
         alias => 'a',
         explicit_alias => 1,
      },
      {
         tbl  => 't2',
         alias => 'b',
         join  => {
            to         => 't1',
            type       => 'left',
            condition  => 'on',
            where      => [
               {
                  predicate => undef,
                  left_arg  => 'a.id',
                  operator  => '=',
                  right_arg => 'b.id',
               },
            ],
            ansi       => 1,
         },
      },
   ],
);

test_from(
   't1 a NATURAL RIGHT OUTER JOIN t2 b',
   [
      {
         tbl  => 't1',
         alias => 'a',
      },
      {
         tbl  => 't2',
         alias => 'b',
         join  => {
            to   => 't1',
            type => 'natural right outer',
            ansi => 1,
         },
      },
   ],
);

# http://pento.net/2009/04/03/join-and-comma-precedence/
test_from(
   'a, b LEFT JOIN c ON c.c = a.a',
   [
      {
         tbl  => 'a',
      },
      {
         tbl  => 'b',
         join  => {
            to   => 'a',
            type => 'inner',
            ansi => 0,
         },
      },
      {
         tbl  => 'c',
         join  => {
            to         => 'b',
            type       => 'left',
            condition  => 'on',
            where      => [
               {
                  predicate => undef,
                  left_arg  => 'c.c',
                  operator  => '=',
                  right_arg => 'a.a',
               },
            ],
            ansi       => 1, 
         },
      },
   ],
);

test_from(
   'a, b, c CROSS JOIN d USING (id)',
   [
      {
         tbl  => 'a',
      },
      {
         tbl  => 'b',
         join  => {
            to   => 'a',
            type => 'inner',
            ansi => 0,
         },
      },
      {
         tbl  => 'c',
         join  => {
            to   => 'b',
            type => 'inner',
            ansi => 0,
         },
      },
      {
         tbl  => 'd',
         join  => {
            to         => 'c',
            type       => 'cross',
            condition  => 'using',
            columns    => ['id'],
            ansi       => 1, 
         },
      },
   ],
);

# Index hints.
test_from(
   'tbl FORCE INDEX (foo)',
   [
      {
         tbl       => 'tbl',
         index_hint => 'FORCE INDEX (foo)',
      }
   ]
);

test_from(
   'tbl USE INDEX(foo)',
   [
      {
         tbl       => 'tbl',
         index_hint => 'USE INDEX(foo)',
      }
   ]
);

test_from(
   'tbl FORCE KEY(foo)',
   [
      {
         tbl       => 'tbl',
         index_hint => 'FORCE KEY(foo)',
      }
   ]
);

test_from(
   'tbl t FORCE KEY(foo)',
   [
      {
         tbl       => 'tbl',
         alias      => 't',
         index_hint => 'FORCE KEY(foo)',
      }
   ]
);

test_from(
   'tbl AS t FORCE KEY(foo)',
   [
      {
         tbl           => 'tbl',
         alias          => 't',
         explicit_alias => 1,
         index_hint     => 'FORCE KEY(foo)',
      }
   ]
);

# Database-qualified tables.
test_from(
   'db.tbl',
   [{
      db   => 'db',
      tbl => 'tbl',
   }],
);

test_from(
   '`db`.`tbl`',
   [{
      db   => 'db',
      tbl => 'tbl',
   }],
);

test_from(
   '`ryan likes`.`to break stuff`',
   [{
      db   => 'ryan likes',
      tbl => 'to break stuff',
   }],
);

test_from(
   '`db`.`tbl` LEFT JOIN `foo`.`bar` USING (glue)',
   [
      {  db   => 'db',
         tbl => 'tbl',
      },
      {  db   => 'foo',
         tbl => 'bar',
         join => {
            to        => 'tbl',
            type      => 'left',
            ansi      => 1,
            condition => 'using',
            columns   => ['glue'],
         },
      },
   ],
);

test_from(
   'tblB AS dates LEFT JOIN dbF.tblC AS scraped ON dates.dt = scraped.dt AND dates.version = scraped.version',
   [
      {
        tbl           => 'tblB',
        alias          => 'dates',
        explicit_alias => 1,
      },
      {
        tbl           => 'tblC',
        alias          => 'scraped',
        explicit_alias => 1,
        db             => 'dbF',
        join           => {
          condition  => 'on',
          ansi       => 1,
          to         => 'tblB',
          type       => 'left',
          where      => [
            {
              predicate => undef,
              left_arg  => 'dates.dt',
              operator  => '=',
              right_arg => 'scraped.dt',
            },
            {
              predicate => 'and',
              left_arg  => 'dates.version',
              operator  => '=',
              right_arg => 'scraped.version',
            },
          ],
        },
      },
   ],
);

# The parser needs to match the join condition verb ON or USING
# but these table names have those words embedded in the full
# table name.
test_from(
   "db.version",
   [ { db=>'db', tbl=>'version', } ],
);

test_from(
   "db.like_using_odd_table_names",
   [ { db=>'db', tbl=>'like_using_odd_table_names', } ],
);

test_from(
   "db.`on`",  # don't name your table this :-(
   [ { db=>'db', tbl=>'on', } ],
);

test_from(
   "db.`using`",  # or this
   [ { db=>'db', tbl=>'using', } ],
);

# #############################################################################
# parse_table_reference()
# #############################################################################
sub test_parse_table_reference {
   my ( $tbl, $struct ) = @_;
   my $s = $sp->parse_table_reference($tbl);
   is_deeply(
      $s,
      $struct,
      $tbl
   );
   return;
}

test_parse_table_reference('tbl',
   { tbl => 'tbl', }
);

test_parse_table_reference('tbl a',
   { tbl => 'tbl', alias => 'a', }
);

test_parse_table_reference('tbl as a',
   { tbl => 'tbl', alias => 'a', explicit_alias => 1, }
);

test_parse_table_reference('tbl AS a',
   { tbl => 'tbl', alias => 'a', explicit_alias => 1, }
);

test_parse_table_reference('db.tbl',
   { tbl => 'tbl', db => 'db', }
);

test_parse_table_reference('db.tbl a',
   { tbl => 'tbl', db => 'db', alias => 'a', }
);

test_parse_table_reference('db.tbl AS a',
   { tbl => 'tbl', db => 'db', alias => 'a', explicit_alias => 1, }
);


test_parse_table_reference('`tbl`',
   { tbl => 'tbl', }
);

test_parse_table_reference('`tbl` `a`',
   { tbl => 'tbl', alias => 'a', }
);

test_parse_table_reference('`tbl` as `a`',
   { tbl => 'tbl', alias => 'a', explicit_alias => 1, }
);

test_parse_table_reference('`tbl` AS `a`',
   { tbl => 'tbl', alias => 'a', explicit_alias => 1, }
);

test_parse_table_reference('`db`.`tbl`',
   { tbl => 'tbl', db => 'db', }
);

test_parse_table_reference('`db`.`tbl` `a`',
   { tbl => 'tbl', db => 'db', alias => 'a', }
);

test_parse_table_reference('`db`.`tbl` AS `a`',
   { tbl => 'tbl', db => 'db', alias => 'a', explicit_alias => 1, }
);

# #############################################################################
# parse_columns()
# #############################################################################
sub test_parse_columns {
   my ( $cols, $struct ) = @_;
   my $s = $sp->parse_columns($cols);
   is_deeply(
      $s,
      $struct,
      $cols,
   );
   return;
}

test_parse_columns('tbl.* foo',
   [ { col => '*', tbl => 'tbl', alias => 'foo' } ],
);

# #############################################################################
# parse_set()
# #############################################################################
sub test_parse_set {
   my ( $set, $struct ) = @_;
   my $got = $sp->parse_set($set);
   is_deeply(
      $got,
      $struct,
      "parse_set($set)"
   ) or print Dumper($got);
}

test_parse_set(
   "col='val'",
   [{col=>"col", value=>"'val'"}],
);

test_parse_set(
   'a.foo="bar", b.foo=NOW()',
   [
      {tbl=>"a", col=>"foo", value=>'"bar"'},
      {tbl=>"b", col=>"foo", value=>'NOW()'},
   ],
);

# #############################################################################
# Subqueries.
# #############################################################################

my $query = "DELETE FROM t1
WHERE s11 > ANY
(SELECT COUNT(*) /* no hint */ FROM t2 WHERE NOT EXISTS
   (SELECT * FROM t3 WHERE ROW(5*t2.s1,77)=
      (SELECT 50,11*s1 FROM
         (SELECT * FROM t5) AS t5
      )
   )
)";
my @subqueries = $sp->remove_subqueries($sp->clean_query($query));
is_deeply(
   \@subqueries,
   [
      'DELETE FROM t1 WHERE s11 > ANY (__SQ3__)',
      {
         query   => 'SELECT * FROM t5',
         context => 'identifier',
         nested  => 1,
      },
      {
         query   => 'SELECT 50,11*s1 FROM __SQ0__ AS t5',
         context => 'scalar',
         nested  => 2,
      },
      {
         query   => 'SELECT * FROM t3 WHERE ROW(5*t2.s1,77)= __SQ1__',
         context => 'list',
         nested  => 3,
      },
      {
         query   => 'SELECT COUNT(*)  FROM t2 WHERE NOT EXISTS (__SQ2__)',
         context => 'list',
      }
   ],
   'DELETE with nested subqueries'
);

$query = "select col from tbl
          where id=(select max(id) from tbl2 where foo='bar') limit 1";
@subqueries = $sp->remove_subqueries($sp->clean_query($query));
is_deeply(
   \@subqueries,
   [
      'select col from tbl where id=__SQ0__ limit 1',
      {
         query   => "select max(id) from tbl2 where foo='bar'",
         context => 'scalar',
      },
   ],
   'Subquery as scalar'
);

$query = "select col from tbl
          where id=(select max(id) from tbl2 where foo='bar') and col in(select foo from tbl3) limit 1";
@subqueries = $sp->remove_subqueries($sp->clean_query($query));
is_deeply(
   \@subqueries,
   [
      'select col from tbl where id=__SQ1__ and col in(__SQ0__) limit 1',
      {
         query   => "select foo from tbl3",
         context => 'list',
      },
      {
         query   => "select max(id) from tbl2 where foo='bar'",
         context => 'scalar',
      },
   ],
   'Subquery as scalar and IN()'
);

$query = "SELECT NOW() AS a1, (SELECT f1(5)) AS a2";
@subqueries = $sp->remove_subqueries($sp->clean_query($query));
is_deeply(
   \@subqueries,
   [
      'SELECT NOW() AS a1, __SQ0__ AS a2',
      {
         query   => "SELECT f1(5)",
         context => 'identifier',
      },
   ],
   'Subquery as SELECT column'
);

$query = "SELECT DISTINCT store_type FROM stores s1
WHERE NOT EXISTS (
SELECT * FROM cities WHERE NOT EXISTS (
SELECT * FROM cities_stores
WHERE cities_stores.city = cities.city
AND cities_stores.store_type = stores.store_type))";
@subqueries = $sp->remove_subqueries(
   $sp->clean_query($sp->normalize_keyword_spaces($query)));
is_deeply(
   \@subqueries,
   [
      'SELECT DISTINCT store_type FROM stores s1 WHERE NOT EXISTS (__SQ1__)',
      {
         query   => "SELECT * FROM cities_stores WHERE cities_stores.city = cities.city AND cities_stores.store_type = stores.store_type",
         context => 'list',
         nested  => 1,
      },
      {
         query   => "SELECT * FROM cities WHERE NOT EXISTS (__SQ0__)",
         context => 'list',
      },
   ],
   'Two nested NOT EXISTS subqueries'
);

$query = "select col from tbl
          where id=(select max(id) from tbl2 where foo='bar')
          and col in(select foo from
            (select b from fn where id=1
               and b > any(select a from a)
            )
         ) limit 1";
@subqueries = $sp->remove_subqueries($sp->clean_query($query));
is_deeply(
   \@subqueries,
   [
      'select col from tbl where id=__SQ3__ and col in(__SQ2__) limit 1',
      {
         query   => 'select a from a',
         context => 'list',
         nested  => 1,
      },
      {
         query   => 'select b from fn where id=1 and b > any(__SQ0__)',
         context => 'identifier',
         nested  => 2,
      },
      {
         query   => 'select foo from __SQ1__',
         context => 'list',
      },
      {
         query   => 'select max(id) from tbl2 where foo=\'bar\'',
         context => 'scalar',
      },
   ],
   'Mutiple and nested subqueries'
);

$query = "select (select now()) from universe";
@subqueries = $sp->remove_subqueries($sp->clean_query($query));
is_deeply(
   \@subqueries,
   [
      'select __SQ0__ from universe',
      {
         query   => 'select now()',
         context => 'identifier',
      },
   ],
   'Subquery as non-aliased column identifier'
);

# #############################################################################
# Test parsing full queries.
# #############################################################################

my @cases = (

   # ########################################################################
   # DELETE
   # ########################################################################
   {  name   => 'DELETE FROM',
      query  => 'DELETE FROM tbl',
      struct => {
         type    => 'delete',
         clauses => { from => 'tbl', },
         from    => [ { tbl => 'tbl', } ],
         unknown => undef,
      },
   },
   {  name   => 'DELETE FROM WHERE',
      query  => 'DELETE FROM tbl WHERE id=1',
      struct => {
         type    => 'delete',
         clauses => { 
            from  => 'tbl ',
            where => 'id=1',
         },
         from    => [ { tbl => 'tbl', } ],
         where   => [
            {
               predicate => undef,
               left_arg  => 'id',
               operator  => '=',
               right_arg => '1',
            },
         ],
         unknown => undef,
      },
   },
   {  name   => 'DELETE FROM LIMIT',
      query  => 'DELETE FROM tbl LIMIT 5',
      struct => {
         type    => 'delete',
         clauses => {
            from  => 'tbl ',
            limit => '5',
         },
         from    => [ { tbl => 'tbl', } ],
         limit   => {
            row_count => 5,
         },
         unknown => undef,
      },
   },
   {  name   => 'DELETE FROM ORDER BY',
      query  => 'DELETE FROM tbl ORDER BY foo',
      struct => {
         type    => 'delete',
         clauses => {
            from     => 'tbl ',
            order_by => 'foo',
         },
         from     => [ { tbl => 'tbl', } ],
         order_by => [{column=>'foo'}],
         unknown  => undef,
      },
   },
   {  name   => 'DELETE FROM WHERE LIMIT',
      query  => 'DELETE FROM tbl WHERE id=1 LIMIT 3',
      struct => {
         type    => 'delete',
         clauses => { 
            from  => 'tbl ',
            where => 'id=1 ',
            limit => '3',
         },
         from    => [ { tbl => 'tbl', } ],
         where   => [
            {
               predicate => undef,
               left_arg  => 'id',
               operator  => '=',
               right_arg  => '1',
            },
         ],
         limit   => {
            row_count => 3,
         },
         unknown => undef,
      },
   },
   {  name   => 'DELETE FROM WHERE ORDER BY',
      query  => 'DELETE FROM tbl WHERE id=1 ORDER BY id',
      struct => {
         type    => 'delete',
         clauses => { 
            from     => 'tbl ',
            where    => 'id=1 ',
            order_by => 'id',
         },
         from     => [ { tbl => 'tbl', } ],
         where   => [
            {
               predicate => undef,
               left_arg  => 'id',
               operator  => '=',
               right_arg => '1',
            },
         ],
         order_by => [{column=>'id'}],
         unknown  => undef,
      },
   },
   {  name   => 'DELETE FROM WHERE ORDER BY LIMIT',
      query  => 'DELETE FROM tbl WHERE id=1 ORDER BY id ASC LIMIT 1 OFFSET 3',
      struct => {
         type    => 'delete',
         clauses => { 
            from     => 'tbl ',
            where    => 'id=1 ',
            order_by => 'id ASC ',
            limit    => '1 OFFSET 3',
         },
         from    => [ { tbl => 'tbl', } ],
         where   => [
            {
               predicate => undef,
               left_arg  => 'id',
               operator  => '=',
               right_arg => '1',
            },
         ],
         order_by=> [{column=>'id', sort=>'ASC'}],
         limit   => {
            row_count       => 1,
            offset          => 3,
            explicit_offset => 1,
         },
         unknown => undef,
      },
   },

   # ########################################################################
   # INSERT
   # ########################################################################
   {  name   => 'INSERT INTO VALUES',
      query  => 'INSERT INTO tbl VALUES (1,"foo")',
      struct => {
         type    => 'insert',
         clauses => { 
            into   => 'tbl',
            values => '(1,"foo")',
         },
         into   => [ { tbl => 'tbl', } ],
         values => [ '1', q{"foo"}, ],
         unknown => undef,
      },
   },
   {  name   => 'INSERT INTO VALUES with complex CSV values',
      query  => 'INSERT INTO tbl VALUES ("hello, world!", "", a, \'b\')',
      struct => {
         type    => 'insert',
         clauses => { 
            into   => 'tbl',
            values => '("hello, world!", "", a, \'b\')',
         },
         into   => [ { tbl => 'tbl', } ],
         values => [
            q{"hello, world!"},
            q{""},
            q{a},
            q{'b'},
         ],
         unknown => undef,
      },
   },
   {  name   => 'INSERT VALUE',
      query  => 'INSERT tbl VALUE (1,"foo")',
      struct => {
         type    => 'insert',
         clauses => { 
            into   => 'tbl',
            values => '(1,"foo")',
         },
         into   => [ { tbl => 'tbl', } ],
         values => [ '1', q{"foo"}, ],
         unknown => undef,
      },
   },
   {  name   => 'INSERT INTO cols VALUES',
      query  => 'INSERT INTO db.tbl (id, name) VALUE (2,"bob")',
      struct => {
         type    => 'insert',
         clauses => { 
            into    => 'db.tbl',
            columns => 'id, name ',
            values  => '(2,"bob")',
         },
         into    => [ { tbl => 'tbl', db => 'db' } ],
         columns => [ { col => 'id' }, { col => 'name' } ],
         values  => [ '2', q{"bob"} ],
         unknown => undef,
      },
   },
   {  name   => 'INSERT INTO VALUES ON DUPLICATE',
      query  => 'INSERT INTO tbl VALUE (3,"bob") ON DUPLICATE KEY UPDATE col1=9',
      struct => {
         type    => 'insert',
         clauses => { 
            into         => 'tbl',
            values       => '(3,"bob")',
            on_duplicate => 'col1=9',
         },
         into         => [ { tbl => 'tbl', } ],
         values       => [ '3', q{"bob"} ],
         on_duplicate => ['col1=9',],
         unknown      => undef,
      },
   },
   {  name   => 'INSERT INTO SET',
      query  => 'INSERT INTO tbl SET id=1, foo=NULL',
      struct => {
         type    => 'insert',
         clauses => { 
            into => 'tbl',
            set  => 'id=1, foo=NULL',
         },
         into    => [ { tbl => 'tbl', } ],
         set     => [
            { col => 'id',  value => '1',    },
            { col => 'foo', value => 'NULL', },
         ],
         unknown => undef,
      },
   },
   {  name   => 'INSERT INTO SET ON DUPLICATE',
      query  => 'INSERT INTO tbl SET i=3 ON DUPLICATE KEY UPDATE col1=9',
      struct => {
         type    => 'insert',
         clauses => { 
            into         => 'tbl',
            set          => 'i=3',
            on_duplicate => 'col1=9',
         },
         into         => [ { tbl => 'tbl', } ],
         set          => [{col =>'i', value=>'3'}],
         on_duplicate => ['col1=9',],
         unknown      => undef,
      },
   },
   {  name   => 'INSERT ... SELECT',
      query  => 'INSERT INTO tbl (col) SELECT id FROM tbl2 WHERE id > 100',
      struct => {
         type    => 'insert',
         clauses => { 
            into    => 'tbl',
            columns => 'col ',
            select  => 'id FROM tbl2 WHERE id > 100',
         },
         into         => [ { tbl => 'tbl', } ],
         columns      => [ { col => 'col' } ],
         select       => {
            type    => 'select',
            clauses => { 
               columns => 'id ',
               from    => 'tbl2 ',
               where   => 'id > 100',
            },
            columns => [ { col => 'id' } ],
            from    => [ { tbl => 'tbl2', } ],
            where   => [
               {
                  predicate => undef,
                  left_arg  => 'id',
                  operator  => '>',
                  right_arg => '100',
               },
            ],
            unknown => undef,
         },
         unknown      => undef,
      },
   },
   {  name   => 'INSERT INTO VALUES()',
      query  => 'INSERT INTO db.tbl (id, name) VALUES(2,"bob")',
      struct => {
         type    => 'insert',
         clauses => { 
            into    => 'db.tbl',
            columns => 'id, name ',
            values  => '(2,"bob")',
         },
         into    => [ { tbl => 'tbl', db => 'db' } ],
         columns => [ { col => 'id' }, { col => 'name' } ],
         values  => [ '2', q{"bob"} ],
         unknown => undef,
      },
   },

   # ########################################################################
   # REPLACE
   # ########################################################################
   # REPLACE are parsed by parse_insert() so if INSERT is well-tested we
   # shouldn't need to test REPLACE much.
   {  name   => 'REPLACE INTO VALUES',
      query  => 'REPLACE INTO tbl VALUES (1,"foo")',
      struct => {
         type    => 'replace',
         clauses => { 
            into   => 'tbl',
            values => '(1,"foo")',
         },
         into   => [ { tbl => 'tbl', } ],
         values => [ '1', q{"foo"} ],
         unknown => undef,
      },
   },
   {  name   => 'REPLACE VALUE',
      query  => 'REPLACE tbl VALUE (1,"foo")',
      struct => {
         type    => 'replace',
         clauses => { 
            into   => 'tbl',
            values => '(1,"foo")',
         },
         into   => [ { tbl => 'tbl', } ],
         values => [ '1', q{"foo"} ],
         unknown => undef,
      },
   },
   {  name   => 'REPLACE INTO cols VALUES',
      query  => 'REPLACE INTO db.tbl (id, name) VALUE (2,"bob")',
      struct => {
         type    => 'replace',
         clauses => { 
            into    => 'db.tbl',
            columns => 'id, name ',
            values  => '(2,"bob")',
         },
         into    => [ { tbl => 'tbl', db => 'db' } ],
         columns => [ { col => 'id' }, { col => 'name' } ],
         values  => [ '2', q{"bob"} ],
         unknown => undef,
      },
   },
   {
      name  => 'REPLACE SELECT JOIN ON',
      query => 'REPLACE INTO db.tblA (dt, ncpc) SELECT dates.dt, scraped.total_r FROM tblB AS dates LEFT JOIN dbF.tblC AS scraped ON dates.dt = scraped.dt AND dates.version = scraped.version',
      struct => {
         type    => 'replace',
         clauses => {
            columns => 'dt, ncpc ',
            into    => 'db.tblA',
            select  => 'dates.dt, scraped.total_r FROM tblB AS dates LEFT JOIN dbF.tblC AS scraped ON dates.dt = scraped.dt AND dates.version = scraped.version',
         },
         columns => [ { col => 'dt' }, { col => 'ncpc' } ],
         into    => [ { db => 'db', tbl => 'tblA' } ],
         select  => {
            type    => 'select',
            clauses => {
               columns => 'dates.dt, scraped.total_r ',
               from    => 'tblB AS dates LEFT JOIN dbF.tblC AS scraped ON dates.dt = scraped.dt AND dates.version = scraped.version',
            },
            columns => [
               { tbl => 'dates',   col => 'dt'      },
               { tbl => 'scraped', col => 'total_r' },
            ],
            from    => [
               {
                 tbl            => 'tblB',
                 alias          => 'dates',
                 explicit_alias => 1,
               },
               {
                 tbl            => 'tblC',
                 alias          => 'scraped',
                 explicit_alias => 1,
                 db             => 'dbF',
                 join           => {
                   condition => 'on',
                   ansi  => 1,
                   to    => 'tblB',
                   type  => 'left',
                   where => [
                     {
                       predicate => undef,
                       left_arg  => 'dates.dt',
                       operator  => '=',
                       right_arg => 'scraped.dt',
                     },
                     {
                       predicate => 'and',
                       left_arg  => 'dates.version',
                       operator  => '=',
                       right_arg => 'scraped.version',
                     },
                   ],
                 },
               },
            ],
            unknown => undef,
         },
         unknown => undef,
      },
   },

   # ########################################################################
   # SELECT
   # ########################################################################
   {  name   => 'SELECT',
      query  => 'SELECT NOW()',
      struct => {
         type    => 'select',
         clauses => { 
            columns => 'NOW()',
         },
         columns => [ { col => 'NOW()' } ],
         unknown => undef,
      },
   },
   {  name   => 'SELECT var',
      query  => 'select @@version_comment',
      struct => {
         type    => 'select',
         clauses => { 
            columns => '@@version_comment',
         },
         columns => [ { col => '@@version_comment' } ],
         unknown => undef,
      },
   },
   {  name   => 'SELECT FROM',
      query  => 'SELECT col1, col2 FROM tbl',
      struct => {
         type    => 'select',
         clauses => { 
            columns => 'col1, col2 ',
            from    => 'tbl',
         },
         columns => [ { col => 'col1' }, { col => 'col2' } ],
         from    => [ { tbl => 'tbl', } ],
         unknown => undef,
      },
   },
   {  name   => 'SELECT FROM JOIN WHERE GROUP BY ORDER BY LIMIT',
      query  => '/* nonsensical but covers all the basic clauses */
         SELECT t1.col1 a, t1.col2 as b
         FROM tbl1 t1
            LEFT JOIN tbl2 AS t2 ON t1.id = t2.id
         WHERE
            t2.col IS NOT NULL
            AND t2.name = "bob"
         GROUP BY a, b
         ORDER BY t2.name ASC
         LIMIT 100, 10
      ',
      struct => {
         type    => 'select',
         clauses => { 
            columns  => 't1.col1 a, t1.col2 as b ',
            from     => 'tbl1 t1 LEFT JOIN tbl2 AS t2 ON t1.id = t2.id ',
            where    => 't2.col IS NOT NULL AND t2.name = "bob" ',
            group_by => 'a, b ',
            order_by => 't2.name ASC ',
            limit    => '100, 10',
         },
         columns => [ { col => 'col1', tbl => 't1', alias => 'a' },
                      { col => 'col2', tbl => 't1', alias => 'b',
                        explicit_alias => 1 } ],
         from    => [
            {
               tbl   => 'tbl1',
               alias => 't1',
            },
            {
               tbl   => 'tbl2',
               alias => 't2',
               explicit_alias => 1,
               join  => {
                  to        => 'tbl1',
                  type      => 'left',
                  condition => 'on',
                  where      => [
                     {
                        predicate => undef,
                        left_arg  => 't1.id',
                        operator  => '=',
                        right_arg => 't2.id',
                     },
                  ],
                  ansi      => 1,
               },
            },
         ],
         where    => [
            {
               predicate => undef,
               left_arg  => 't2.col',
               operator  => 'is not',
               right_arg => 'null',
            },
            {
               predicate => 'and',
               left_arg  => 't2.name',
               operator  => '=',
               right_arg => '"bob"',
            },
         ],
         group_by => [
            { column => 'a' },
            { column => 'b' },
         ],
         order_by => [{table=>'t2', column=>'name', sort=>'ASC'}],
         limit    => {
            row_count => 10,
            offset    => 100,
         },
         unknown => undef,
      },
   },
   {  name   => 'SELECT FROM JOIN ON() JOIN USING() WHERE',
      query  => 'SELECT t1.col1 a, t1.col2 as b

         FROM tbl1 t1

            JOIN tbl2 AS t2 ON(t1.id = t2.id)

            JOIN tbl3 t3 USING(id) 

         WHERE
            t2.col IS NOT NULL',
      struct => {
         type    => 'select',
         clauses => { 
            columns  => 't1.col1 a, t1.col2 as b ',
            from     => 'tbl1 t1 JOIN tbl2 AS t2 on (t1.id = t2.id) JOIN tbl3 t3 using (id) ',
            where    => 't2.col IS NOT NULL',
         },
         columns => [ { col => 'col1', tbl => 't1', alias => 'a' },
                      { col => 'col2', tbl => 't1', alias => 'b',
                        explicit_alias => 1 } ],
         from    => [
            {
               tbl   => 'tbl1',
               alias => 't1',
            },
            {
               tbl   => 'tbl2',
               alias => 't2',
               explicit_alias => 1,
               join  => {
                  to        => 'tbl1',
                  type      => 'inner',
                  condition => 'on',
                  where      => [
                     {
                        predicate => undef,
                        left_arg  => 't1.id',
                        operator  => '=',
                        right_arg => 't2.id',
                     },
                  ],
                  ansi      => 1,
               },
            },
            {
               tbl   => 'tbl3',
               alias => 't3',
               join  => {
                  to        => 'tbl2',
                  type      => 'inner',
                  condition => 'using',
                  columns   => ['id'],
                  ansi      => 1,
               },
            },
         ],
         where    => [
            {
               predicate => undef,
               left_arg  => 't2.col',
               operator  => 'is not',
               right_arg => 'null',
            },
         ],
         unknown => undef,
      },
   },
   {  name   => 'SELECT keywords',
      query  => 'SELECT all high_priority SQL_CALC_FOUND_ROWS NOW() LOCK IN SHARE MODE',
      struct => {
         type     => 'select',
         clauses  => { 
            columns => 'NOW()',
         },
         columns  => [ { col => 'NOW()' } ],
         keywords => {
            all                 => 1,
            high_priority       => 1,
            sql_calc_found_rows => 1,
            lock_in_share_mode  => 1,
         },
         unknown  => undef,
      },
   },
   { name   => 'SELECT * FROM WHERE',
     query  => 'SELECT * FROM tbl WHERE ip="127.0.0.1"',
     struct => {
         type     => 'select',
         clauses  => { 
            columns => '* ',
            from    => 'tbl ',
            where   => 'ip="127.0.0.1"',
         },
         columns  => [ { col => '*' } ],
         from     => [ { tbl => 'tbl' } ],
         where    => [
            {
               predicate => undef,
               left_arg  => 'ip',
               operator  => '=',
               right_arg => '"127.0.0.1"',
            },
         ],
         unknown  => undef,
      },
   },
   { name    => 'SELECT with simple subquery',
     query   => 'select * from t where id in(select col from t2)',
     struct  => {
         type    => 'select',
         clauses => { 
            columns => '* ',
            from    => 't ',
            where   => 'id in(__SQ0__)',
         },
         columns    => [ { col => '*' } ],
         from       => [ { tbl => 't' } ],
         where      => [
            {
               predicate => undef,
               left_arg  => 'id',
               operator  => 'in',
               right_arg => '(__SQ0__)',
            },
         ],
         unknown    => undef,
         subqueries => [
            {
               query   => 'select col from t2',
               context => 'list',
               type    => 'select',
               clauses => { 
                  columns => 'col ',
                  from    => 't2',
               },
               columns    => [ { col => 'col' } ],
               from       => [ { tbl => 't2' } ],
               unknown    => undef,
            },
         ],
      },
   },
   { name    => 'Complex SELECT, multiple JOIN and subqueries',
     query   => 'select now(), (select foo from bar where id=1)
                 from t1, t2 join (select * from sqt1) as t3 using (`select`)
                 join t4 on t4.id=t3.id 
                 where c1 > any(select col2 as z from sqt2 zz
                    where sqtc<(select max(col) from l where col<100))
                 and s in ("select", "tricky") or s <> "select"
                 group by 1 limit 10',
      struct => {
         type       => 'select',
         clauses    => { 
            columns  => 'now(), __SQ3__ ',
            from     => 't1, t2 join __SQ2__ as t3 using (`select`) join t4 on t4.id=t3.id ',
            where    => 'c1 > any(__SQ1__) and s in ("select", "tricky") or s <> "select" ',
            group_by => '1 ',
            limit    => '10',
         },
         columns    => [ { col => 'now()' }, { col => '__SQ3__' } ],
         from       => [
            {
               tbl => 't1',
            },
            {
               tbl  => 't2',
               join => {
                  to   => 't1',
                  ansi => 0,
                  type => 'inner',
               },
            },
            {
               tbl => '__SQ2__',
               alias => 't3',
               explicit_alias => 1,
               join  => {
                  to   => 't2',
                  ansi => 1,
                  type => 'inner',
                  columns    => ['`select`'],
                  condition  => 'using',
               },
            },
            {
               tbl => 't4',
               join => {
                  to   => '__SQ2__',
                  ansi => 1,
                  type => 'inner',
                  where      => [
                     {
                        predicate => undef,
                        left_arg  => 't4.id',
                        operator  => '=',
                        right_arg => 't3.id',
                     },
                  ],
                  condition  => 'on',
               },
            },
         ],
         where      => [
            {
               predicate => undef,
               left_arg  => 'c1',
               operator  => '>',
               right_arg => 'any(__SQ1__)',
            },
            {
               predicate => 'and',
               left_arg  => 's',
               operator  => 'in',
               right_arg => '("select", "tricky")',
            },
            {
               predicate => 'or',
               left_arg  => 's',
               operator  => '<>',
               right_arg => '"select"',
            },
         ],
         limit      => { row_count => 10 },
         group_by   => [ { position => '1' } ],
         unknown    => undef,
         subqueries => [
            {
               clauses => {
                  columns => 'max(col) ',
                  from    => 'l ',
                  where   => 'col<100'
               },
               columns => [ { col => 'col', func => 'MAX' } ],
               context => 'scalar',
               from    => [ { tbl => 'l' } ],
               nested  => 1,
               query   => 'select max(col) from l where col<100',
               type    => 'select',
               unknown => undef,
               where   => [
                  {
                     predicate => undef,
                     left_arg  => 'col',
                     operator  => '<',
                     right_arg => '100',
                  },
               ],
            },
            {
               clauses  => {
                  columns => 'col2 as z ',
                  from    => 'sqt2 zz ',
                  where   => 'sqtc<__SQ0__'
               },
               columns => [
                  { alias => 'z', explicit_alias => 1, col => 'col2' }
               ],
               context  => 'list',
               from     => [ { alias => 'zz', tbl => 'sqt2' } ],
               query    => 'select col2 as z from sqt2 zz where sqtc<__SQ0__',
               type     => 'select',
               unknown  => undef,
               where    => [
                  {
                     predicate => undef,
                     left_arg  => 'sqtc',
                     operator  => '<',
                     right_arg => '__SQ0__',
                  },
               ],
            },
            {
               clauses  => {
                  columns => '* ',
                  from    => 'sqt1'
               },
               columns  => [ { col => '*' } ],
               context  => 'identifier',
               from     => [ { tbl => 'sqt1' } ],
               query    => 'select * from sqt1',
               type     => 'select',
               unknown  => undef
            },
            {
               clauses  => {
               columns  => 'foo ',
                  from  => 'bar ',
                  where => 'id=1'
               },
               columns  => [ { col => 'foo' } ],
               context  => 'identifier',
               from     => [ { tbl => 'bar' } ],
               query    => 'select foo from bar where id=1',
               type     => 'select',
               unknown  => undef,
               where    => [
                  {
                     predicate => undef,
                     left_arg  => 'id',
                     operator  => '=',
                     right_arg => '1',
                  },
               ],
            },
         ],
      },
   },
   {  name   => 'Table joined twice',
      query  => "SELECT *
                 FROM   `w_chapter`
                 INNER JOIN `w_series` AS `w_chapter__series`
                 ON `w_chapter`.`series_id` = `w_chapter__series`.`id`,
                 `w_series`,
                 `auth_user`
                 WHERE `w_chapter`.`status` = 1",
      struct => {
         type    => 'select',
         clauses => { 
            columns => "* ",
            from    => "`w_chapter` INNER JOIN `w_series` AS `w_chapter__series` ON `w_chapter`.`series_id` = `w_chapter__series`.`id`, `w_series`, `auth_user` ",
            where   => "`w_chapter`.`status` = 1",
         },
         columns => [{col => '*'}],
         from    => [
          {
            tbl => 'w_chapter'
          },
          {
            alias => 'w_chapter__series',
            explicit_alias => 1,
            join => {
              ansi => 1,
              condition => 'on',
               where      => [
                  {
                     predicate => undef,
                     left_arg  => '`w_chapter`.`series_id`',
                     operator  => '=',
                     right_arg => '`w_chapter__series`.`id`',
                  },
               ],
              to => 'w_chapter',
              type => 'inner'
            },
            tbl => 'w_series'
          },
          {
            join => {
              ansi => 0,
              to => 'w_series',
              type => 'inner'
            },
            tbl => 'w_series'
          },
          {
            join => {
              ansi => 0,
              to => 'w_series',
              type => 'inner'
            },
            tbl => 'auth_user'
          }
         ],
         where   => [
            {
               predicate => undef,
               left_arg  => '`w_chapter`.`status`',
               operator  => '=',
               right_arg => '1',
            },
         ],
         unknown => undef,
      },
   },

   # ########################################################################
   # UPDATE
   # ########################################################################
   {  name   => 'UPDATE SET',
      query  => 'UPDATE tbl SET col=1',
      struct => {
         type    => 'update',
         clauses => { 
            tables => 'tbl ',
            set    => 'col=1',
         },
         tables  => [ { tbl => 'tbl', } ],
         set     => [ { col =>'col', value => '1' } ],
         unknown => undef,
      },
   },
   {  name   => 'UPDATE SET WHERE ORDER BY LIMIT',
      query  => 'UPDATE tbl AS t SET foo=NULL WHERE foo IS NOT NULL ORDER BY id LIMIT 10',
      struct => {
         type    => 'update',
         clauses => { 
            tables   => 'tbl AS t ',
            set      => 'foo=NULL ',
            where    => 'foo IS NOT NULL ',
            order_by => 'id ',
            limit    => '10',
         },
         tables   => [ { tbl => 'tbl', alias => 't', explicit_alias => 1, } ],
         set      => [ { col => 'foo', value => 'NULL' } ],
         where    => [
            {
               predicate => undef,
               left_arg  => 'foo',
               operator  => 'is not',
               right_arg => 'null',
            },
         ],
         order_by => [{column=>'id'}],
         limit    => { row_count => 10 },
         unknown => undef,
      },
   },

   # ########################################################################
   # EXPLAIN EXTENDED fully-qualified queries.
   # ########################################################################
   {  name   => 'EXPLAIN EXTENDED SELECT',
      query  => 'select `sakila`.`city`.`country_id` AS `country_id` from `sakila`.`city` where (`sakila`.`city`.`country_id` = 1)',
      struct => {
         type    => 'select',
         clauses => { 
            columns => '`sakila`.`city`.`country_id` AS `country_id` ',
            from    => '`sakila`.`city` ',
            where   => '(`sakila`.`city`.`country_id` = 1)',
         },
         columns => [
            { db    => 'sakila',
              tbl   => 'city',
              col   => 'country_id',
              alias => 'country_id',
              explicit_alias => 1,
            },
         ],
         from    => [ { db=>'sakila', tbl=>'city' } ],
         where   => [ {
            predicate => undef,
            left_arg  => '`sakila`.`city`.`country_id`',
            operator  => '=',
            right_arg => '1',
         } ],
         unknown => undef,
      },
   },
);

foreach my $test ( @cases ) {
   my $struct = $sp->parse($test->{query});
   is_deeply(
      $struct,
      $test->{struct},
      $test->{name},
   ) or print Dumper($struct);
   die if $test->{stop};
}

# ############################################################################
# Use Schema to achieve full awesomeness.
# ############################################################################
use OptionParser;
use DSNParser;
use Quoter;
use TableParser;
use FileIterator;
use Schema;
use SchemaIterator;

my $o  = new OptionParser(description => 'SchemaIterator');
$o->get_specs("$trunk/bin/pt-table-checksum");

my $q          = new Quoter;
my $tp         = new TableParser(Quoter => $q);
my $fi         = new FileIterator();
my $file_itr   = $fi->get_file_itr("$trunk/t/lib/samples/mysqldump-no-data/dump001.txt");
my $schema     = new Schema();
my $schema_itr = new SchemaIterator(
   file_itr     => $file_itr,
   OptionParser => $o,
   Quoter       => $q,
   TableParser  => $tp,
   keep_ddl     => 1,
   Schema       => $schema,
);
# Init schema.
1 while ($schema_itr->next());

# Notice how c3 and b aren't qualified.
is_deeply(
   $sp->parse("select c3 from b where 'foo'=c3"),
   {
      type     => 'select',
      clauses  => {
         columns => 'c3 ',
         from    => 'b ',
         where   => '\'foo\'=c3',
      },
      columns  => [ { col => 'c3' } ],
      from     => [ { tbl => 'b' } ],
      where    => [ {
         left_arg  => "'foo'",
         operator  => '=',
         right_arg => 'c3',
         predicate => undef,
      } ],
      unknown  => undef,
   },
   "Query struct without Schema"
);

# Now they're qualified.
$sp->set_Schema($schema);
is_deeply(
   $sp->parse("select c3 from b where 'foo'=c3"),
   {
      type     => 'select',
      clauses  => {
         columns => 'c3 ',
         from    => 'b ',
         where   => '\'foo\'=c3',
      },
      columns  => [ { db => 'test', tbl => 'b', col => 'c3' } ],
      from     => [ { db => 'test', tbl => 'b' } ],
      where    => [ {
         left_arg  => "'foo'",
         operator  => '=',
         right_arg => 'c3',
         predicate => undef,
      } ],
      unknown  => undef,
   },
   "Query struct with Schema"
);

# #############################################################################
# Done.
# #############################################################################
exit;
