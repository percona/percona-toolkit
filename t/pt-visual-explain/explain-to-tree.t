#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 60;

use PerconaTest;
require "$trunk/bin/pt-visual-explain";

my $e = new ExplainTree;
my $t;

$t = $e->parse('');
is_deeply( $t, undef, 'No valid input' );

$t = $e->parse( load_file("t/pt-visual-explain/samples/fulltext.sql") );
## Please see file perltidy.ERR
is_deeply(
   $t,
   {  type     => 'Filter with WHERE',
      id       => 1,
      rowid    => 0,
      children => [
         {  type     => 'Bookmark lookup',
            children => [
               {  type          => 'Fulltext scan',
                  key_len       => undef,
                  possible_keys => 'a',
                  ref           => undef,
                  rows          => '1',
                  partitions    => undef,
                  key           => 'foo->a'
               },
               {  type          => 'Table',
                  table         => 'foo',
                  partitions    => undef,
                  possible_keys => 'a',
               },
            ],
         },
      ],
   },
   'Fulltext query',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/impossible_where.sql") );
is_deeply(
   $t,
   {  type  => 'IMPOSSIBLE',
      id    => 1,
      rowid => 0,
      warning => 'Impossible WHERE noticed after reading const tables',
   },
   'Impossible WHERE',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/impossible_having.sql") );
is_deeply(
   $t,
   {  type  => 'IMPOSSIBLE',
      id    => 1,
      rowid => 0,
      warning => 'Impossible HAVING',
   },
   'Impossible HAVING',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/const_row_not_found.sql") );
is_deeply(
   $t,
   {  type     => 'UNION RESULT',
      children => [
         {  type     => 'Constant table access',
            id       => 1,
            rowid    => 0,
            rows     => undef,
            warning  => 'const row not found',
            children => [
               {  type          => 'Table',
                  partitions    => undef,
                  possible_keys => undef,
                  table         => 't1',
               },
            ],
         },
         {  type     => 'SUBQUERY',
            id       => 2,
            rowid    => 1,
            children => [
               {  type     => 'Table scan',
                  id       => 2,
                  rowid    => 4,
                  rows     => undef,
                  children => [
                     {  type          => 'UNION',
                        table         => 'union(<none>,t12)',
                        possible_keys => undef,
                        partitions    => undef,
                        children      => [
                           {  type     => 'SUBQUERY',
                              children => [
                                 {  type  => 'SUBQUERY',
                                    id    => 2,
                                    rowid => 1,
                                 },
                                 {  type    => 'IMPOSSIBLE',
                                    id      => 3,
                                    rowid   => 2,
                                 },
                              ],
                           },
                           {  type     => 'Constant table access',
                              warning  => 'const row not found',
                              id       => 4,
                              rowid    => 3,
                              rows     => undef,
                              children => [
                                 {  type          => 'Table',
                                    table         => 't12',
                                    partitions    => undef,
                                    possible_keys => undef,
                                 },
                              ],
                           },
                        ],
                     },
                  ],
               },
            ],
         },
      ],
   },
   'Const row not found',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/dual_union_in_subquery.sql") );
is_deeply(
   $t,
   {  type     => 'UNION RESULT',
      children => [
         {  id    => 1,
            type  => 'DUAL',
            rowid => 0,
         },
         {  id       => 2,
            type     => 'DEPENDENT SUBQUERY',
            rowid    => 1,
            children => [
               {  type     => 'Table scan',
                  rows     => undef,
                  rowid    => 3,
                  id       => 2,
                  children => [
                     {  type          => 'UNION',
                        partitions    => undef,
                        possible_keys => undef,
                        table         => 'union(<none>,<none>)',
                        children      => [
                           {  id    => 2,
                              type  => 'DEPENDENT SUBQUERY',
                              rowid => 1
                           },
                           {  id    => 3,
                              type  => 'DEPENDENT UNION',
                              rowid => 2
                           }
                        ],
                     }
                  ],
               }
            ],
         }
      ],
   },
   'UNION of DUAL in a subquery',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/no_const_row.sql") );
is_deeply(
   $t,
   {  type     => 'Constant table access',
      id       => 1,
      rowid    => 0,
      rows     => undef,
      warning  => 'const row not found',
      children => [
         {  type          => 'Table',
            table         => 't1',
            possible_keys => undef,
            partitions    => undef,
         },
      ],
   },
   'No constant row found',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/unique_row_not_found.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type     => 'JOIN',
            children => [
               {  type     => 'Bookmark lookup',
                  rowid    => 0,
                  id       => 1,
                  children => [
                     {  key_len       => '4',
                        possible_keys => 'PRIMARY',
                        ref           => 'const',
                        type          => 'Constant index lookup',
                        rows          => '1',
                        partitions    => undef,
                        key           => 'user->PRIMARY'
                     },
                     {  possible_keys => 'PRIMARY',
                        table         => 'user',
                        type          => 'Table',
                        partitions    => undef
                     }
                  ],
               },
               {  type     => 'Bookmark lookup',
                  rowid    => 1,
                  warning  => 'unique row not found',
                  id       => 1,
                  children => [
                     {  key_len       => '2',
                        possible_keys => 'PRIMARY',
                        ref           => 'const',
                        type          => 'Constant index lookup',
                        rows          => undef,
                        partitions    => undef,
                        key           => 'avatar->PRIMARY'
                     },
                     {  possible_keys => 'PRIMARY',
                        table         => 'avatar',
                        type          => 'Table',
                        partitions    => undef
                     }
                  ],
               }
            ],
         },
         {  type     => 'Bookmark lookup',
            rowid    => 2,
            warning  => 'unique row not found',
            id       => 1,
            children => [
               {  key_len       => '4',
                  possible_keys => 'PRIMARY',
                  ref           => 'const',
                  type          => 'Constant index lookup',
                  rows          => undef,
                  partitions    => undef,
                  key           => 'customavatar->PRIMARY'
               },
               {  possible_keys => 'PRIMARY',
                  table         => 'customavatar',
                  type          => 'Table',
                  partitions    => undef
               }
            ],
         }
      ],
   },
   'Unique row not found',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/no_min_max_row.sql") );
is_deeply(
   $t,
   {  type    => 'IMPOSSIBLE',
      warning => 'No matching min/max row',
      id      => 1,
      rowid   => 0,
   },
   'No min/max row',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/simple_partition.sql") );
is_deeply(
   $t,
   {  type     => 'Filesort',
      id       => 1,
      rowid    => 0,
      children => [
         {  type     => 'Table scan',
            rows     => 10,
            children => [
               {  type          => 'Table',
                  table         => 'trb1',
                  possible_keys => undef,
                  partitions    => 'p0,p1,p2,p3',
               },
            ],
         },
      ],
   },
   'Partition',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/full_scan_sakila_film.sql") );
is_deeply(
   $t,
   {  type     => 'Table scan',
      id       => 1,
      rowid    => 0,
      rows     => 935,
      children => [
         {  type          => 'Table',
            table         => 'film',
            possible_keys => undef,
            partitions    => undef,
         }
      ]
   },
   'Simple scan',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/actor_join_film_ref.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type     => 'Table scan',
            rows     => 952,
            id       => 1,
            rowid    => 0,
            children => [
               {  type          => 'Table',
                  table         => 'film',
                  possible_keys => 'PRIMARY',
                  partitions    => undef,
               }
            ],
         },
         {  type     => 'Bookmark lookup',
            id       => 1,
            rowid    => 1,
            children => [
               {  type          => 'Index lookup',
                  key           => 'film_actor->idx_fk_film_id',
                  key_len       => 2,
                  'ref'         => 'sakila.film.film_id',
                  rows          => 2,
                  possible_keys => 'idx_fk_film_id',
                  partitions    => undef,
               },
               {  type          => 'Table',
                  table         => 'film_actor',
                  possible_keys => 'idx_fk_film_id',
                  partitions    => undef,
               },
            ],
         },
      ],
   },
   'Simple join',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/join_buffer.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type     => 'JOIN',
            children => [
               {  type     => 'Table scan',
                  rows     => 10,
                  id       => 1,
                  rowid    => 0,
                  children => [
                     {  type          => 'Table',
                        table         => 't1',
                        possible_keys => undef,
                        partitions    => undef,
                     }
                  ],
               },
               {  type     => 'Filter with WHERE',
                  id       => 1,
                  rowid    => 1,
                  children => [
                     {  type     => 'Bookmark lookup',
                        children => [
                           {  type          => 'Index lookup',
                              key           => 't2->key1',
                              key_len       => 5,
                              'ref'         => 'test.t1.col1',
                              rows          => 2,
                              possible_keys => 'key1',
                              partitions    => undef,
                           },
                           {  type          => 'Table',
                              table         => 't2',
                              possible_keys => 'key1',
                              partitions    => undef,
                           },
                        ],
                     },
                  ],
               },
            ],
         },
         {  type     => 'Join buffer',
            id       => 1,
            rowid    => 2,
            children => [
               {  type     => 'Filter with WHERE',
                  children => [
                     {  type     => 'Bookmark lookup',
                        children => [
                           {  type          => 'Index range scan',
                              key           => 't3->key1',
                              key_len       => 5,
                              'ref'         => undef,
                              rows          => 40,
                              possible_keys => 'key1',
                              partitions    => undef,
                           },
                           {  type          => 'Table',
                              table         => 't3',
                              possible_keys => 'key1',
                              partitions    => undef,
                           },
                        ],
                     },
                  ],
               },
            ],
         },
      ],
   },
   'Three-way join with buffer',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/range_check.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type     => 'Filter with WHERE',
            id       => 1,
            rowid    => 0,
            children => [
               {  type     => 'Bookmark lookup',
                  children => [
                     {  type          => 'Index lookup',
                        rows          => 5,
                        key           => 'v->OXROOTID',
                        key_len       => 32,
                        'ref'         => 'const',
                        possible_keys => 'OXLEFT,OXRIGHT,OXROOTID',
                        partitions    => undef,
                     },
                     {  type          => 'Table',
                        table         => 'v',
                        possible_keys => 'OXLEFT,OXRIGHT,OXROOTID',
                        partitions    => undef,
                     },
                  ],
               },
            ],
         },
         {
            type => 'Re-evaluate indexes each row',
            id            => 1,
            rowid         => 1,
            possible_keys => '3',
            children      => [
               {  type     => 'Table scan',
                  rows     => 5,
                  children => [
                     {  type          => 'Table',
                        table         => 's',
                        possible_keys => 'OXLEFT',
                        partitions    => undef,
                     },
                  ],
               },
            ],
         },
      ],
   },
   'Join that uses a range check',
);

is_deeply(
   $e->parse( load_file("t/pt-visual-explain/samples/range_check_3.sql") ),
   $t,
   'Key map same when decimal as when hex',
);

is_deeply(
   $e->parse( load_file("t/pt-visual-explain/samples/range_check_2.sql") ),
   $t,
   'Key map same as index map',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/not_exists.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type          => 'Index scan',
            rows          => 951,
            id            => 1,
            rowid         => 0,
            key           => 'film->idx_fk_language_id',
            key_len       => 1,
            'ref'         => undef,
            possible_keys => undef,
            partitions    => undef,
         },
         {  type     => 'Distinct/Not-Exists',
            id       => 1,
            rowid    => 1,
            children => [
               {  type     => 'Filter with WHERE',
                  children => [
                     {  type          => 'Index lookup',
                        key           => 'film_actor->idx_fk_film_id',
                        key_len       => 2,
                        'ref'         => 'sakila.film.film_id',
                        rows          => 2,
                        possible_keys => 'idx_fk_film_id',
                        partitions    => undef,
                     },
                  ],
               },
            ],
         },
      ],
   },
   'Join that uses Not exists',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/join_temporary_with_where_distinct.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type     => 'Table scan',
            rows     => undef,
            id       => 1,
            rowid    => 0,
            children => [
               {  type          => 'TEMPORARY',
                  table         => 'temporary(film)',
                  possible_keys => undef,
                  partitions    => undef,
                  children      => [
                     {  type     => 'Filter with WHERE',
                        children => [
                           {  type     => 'Table scan',
                              rows     => 951,
                              children => [
                                 {  type          => 'Table',
                                    table         => 'film',
                                    possible_keys => 'PRIMARY',
                                    partitions    => undef,
                                 },
                              ],
                           },
                        ],
                     },
                  ],
               },
            ],
         },
         {  type     => 'Distinct/Not-Exists',
            id       => 1,
            rowid    => 1,
            children => [
               {  type          => 'Index lookup',
                  key           => 'film_actor->idx_fk_film_id',
                  possible_keys => 'idx_fk_film_id',
                  partitions    => undef,
                  key_len       => 2,
                  'ref'         => 'sakila.film.film_id',
                  rows          => 2,
               },
            ],
         },
      ],
   },
   'Join that uses a temp table, WHERE, and Distinct',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/simple_join_three_tables.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type     => 'JOIN',
            children => [
               {  type          => 'Index scan',
                  key           => 'actor_1->PRIMARY',
                  possible_keys => 'PRIMARY',
                  partitions    => undef,
                  key_len       => 2,
                  'ref'         => undef,
                  rows          => 200,
                  id            => 1,
                  rowid         => 0,
               },
               {  type          => 'Unique index lookup',
                  key           => 'actor_2->PRIMARY',
                  possible_keys => 'PRIMARY',
                  partitions    => undef,
                  key_len       => 2,
                  'ref'         => 'sakila.actor_1.actor_id',
                  rows          => 1,
                  id            => 1,
                  rowid         => 1,
               },
            ],
         },
         {  type          => 'Unique index lookup',
            key           => 'actor_3->PRIMARY',
            possible_keys => 'PRIMARY',
            partitions    => undef,
            key_len       => 2,
            'ref'         => 'sakila.actor_1.actor_id',
            rows          => 1,
            id            => 1,
            rowid         => 2,
         },
      ],
   },
   'Simple join over three tables',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/film_join_actor_eq_ref.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type     => 'Table scan',
            rows     => 5143,
            id       => 1,
            rowid    => 0,
            children => [
               {  type          => 'Table',
                  table         => 'film_actor',
                  possible_keys => 'idx_fk_film_id',
                  partitions    => undef,
               },
            ]
         },
         {  type     => 'Bookmark lookup',
            id       => 1,
            rowid    => 1,
            children => [
               {  type          => 'Unique index lookup',
                  key           => 'film->PRIMARY',
                  key_len       => 2,
                  'ref'         => 'sakila.film_actor.film_id',
                  rows          => 1,
                  possible_keys => 'PRIMARY',
                  partitions    => undef,
               },
               {  type          => 'Table',
                  table         => 'film',
                  possible_keys => 'PRIMARY',
                  partitions    => undef,
               },
            ],
         },
      ],
   },
   'Straight join',
);

$t = $e->parse(
   load_file("t/pt-visual-explain/samples/film_join_actor_eq_ref.sql"),
   { clustered => 1 },
);
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type     => 'Table scan',
            rows     => 5143,
            id       => 1,
            rowid    => 0,
            children => [
               {  type          => 'Table',
                  table         => 'film_actor',
                  possible_keys => 'idx_fk_film_id',
                  partitions    => undef,
               },
            ]
         },
         {  type          => 'Unique index lookup',
            id            => 1,
            rowid         => 1,
            key           => 'film->PRIMARY',
            possible_keys => 'PRIMARY',
            partitions    => undef,
            key_len       => 2,
            'ref'         => 'sakila.film_actor.film_id',
            rows          => 1,
         },
      ],
   },
   'Straight join assuming clustered PK',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/full_row_pk_lookup_sakila_film.sql") );
is_deeply(
   $t,
   {  type     => 'Bookmark lookup',
      id       => 1,
      rowid    => 0,
      children => [
         {  type          => 'Constant index lookup',
            key           => 'film->PRIMARY',
            key_len       => 2,
            'ref'         => 'const',
            rows          => 1,
            possible_keys => 'PRIMARY',
            partitions    => undef,
         },
         {  type          => 'Table',
            table         => 'film',
            possible_keys => 'PRIMARY',
            partitions    => undef,
         },
      ],
   },
   'Constant lookup',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/index_scan_sakila_film.sql") );
is_deeply(
   $t,
   {  type     => 'Bookmark lookup',
      id       => 1,
      rowid    => 0,
      children => [
         {  type          => 'Index scan',
            key           => 'film->idx_title',
            key_len       => 767,
            'ref'         => undef,
            rows          => 952,
            possible_keys => undef,
            partitions    => undef,
         },
         {  type          => 'Table',
            table         => 'film',
            possible_keys => undef,
            partitions    => undef,
         },
      ],
   },
   'Index scan',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/index_scan_sakila_film_using_where.sql") );
is_deeply(
   $t,
   {  type     => 'Filter with WHERE',
      id       => 1,
      rowid    => 0,
      children => [
         {  type     => 'Bookmark lookup',
            children => [
               {  type          => 'Index scan',
                  key           => 'film->idx_title',
                  key_len       => 767,
                  'ref'         => undef,
                  rows          => 952,
                  possible_keys => undef,
                  partitions    => undef,
               },
               {  type          => 'Table',
                  table         => 'film',
                  possible_keys => undef,
                  partitions    => undef,
               },
            ],
         },
      ],
   },
   'Index scan with WHERE clause',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/pk_lookup_sakila_film.sql") );
is_deeply(
   $t,
   {  type          => 'Constant index lookup',
      key           => 'film->PRIMARY',
      possible_keys => 'PRIMARY',
      partitions    => undef,
      key_len       => 2,
      'ref'         => 'const',
      rows          => 1,
      id            => 1,
      rowid         => 0,
   },
   'PK lookup with covering index',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/film_join_actor_const.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type     => 'Bookmark lookup',
            id       => 1,
            rowid    => 0,
            children => [
               {  type          => 'Constant index lookup',
                  key           => 'film->PRIMARY',
                  key_len       => 2,
                  'ref'         => 'const',
                  rows          => 1,
                  possible_keys => 'PRIMARY',
                  partitions    => undef,
               },
               {  type          => 'Table',
                  table         => 'film',
                  possible_keys => 'PRIMARY',
                  partitions    => undef,
               },
            ],
         },
         {  type     => 'Bookmark lookup',
            id       => 1,
            rowid    => 1,
            children => [
               {  type          => 'Index lookup',
                  key           => 'film_actor->idx_fk_film_id',
                  key_len       => 2,
                  'ref'         => 'const',
                  rows          => 10,
                  possible_keys => 'idx_fk_film_id',
                  partitions    => undef,
               },
               {  type          => 'Table',
                  table         => 'film_actor',
                  possible_keys => 'idx_fk_film_id',
                  partitions    => undef,
               },
            ],
         },
      ],
   },
   'Join from constant lookup in film to const ref in film_actor',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/film_join_actor_const_using_index.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type          => 'Constant index lookup',
            key           => 'film->PRIMARY',
            possible_keys => 'PRIMARY',
            partitions    => undef,
            key_len       => 2,
            'ref'         => 'const',
            rows          => 1,
            id            => 1,
            rowid         => 0,
         },
         {  type          => 'Index lookup',
            key           => 'film_actor->idx_fk_film_id',
            possible_keys => 'idx_fk_film_id',
            partitions    => undef,
            key_len       => 2,
            'ref'         => 'const',
            rows          => 10,
            id            => 1,
            rowid         => 1,
         },
      ],
   },
   'Join from const film to const ref film_actor with covering index',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/film_range_on_pk.sql") );
is_deeply(
   $t,
   {  type     => 'Filter with WHERE',
      id       => 1,
      rowid    => 0,
      children => [
         {  type     => 'Bookmark lookup',
            children => [
               {  type          => 'Index range scan',
                  key           => 'film->PRIMARY',
                  key_len       => 2,
                  'ref'         => undef,
                  rows          => 20,
                  possible_keys => 'PRIMARY',
                  partitions    => undef,
               },
               {  type          => 'Table',
                  table         => 'film',
                  possible_keys => 'PRIMARY',
                  partitions    => undef,
               },
            ],
         },
      ],
   },
   'Index range scan with WHERE clause',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/loose_index_scan.sql") );
is_deeply(
   $t,
   {  type          => 'Loose index scan',
      key           => 'film->idx_fk_language_id',
      key_len       => 1,
      'ref'         => undef,
      rows          => 2,
      id            => 1,
      rowid         => 0,
      possible_keys => undef,
      partitions    => undef,
   },
   'Loose index scan',
);

$t = $e->parse(
   load_file("t/pt-visual-explain/samples/film_ref_or_null_on_original_language_id.sql") );
is_deeply(
   $t,
   {  type     => 'Filter with WHERE',
      id       => 1,
      rowid    => 0,
      children => [
         {  type     => 'Bookmark lookup',
            children => [
               {  type          => 'Index lookup with extra null lookup',
                  key           => 'film->idx_fk_original_language_id',
                  key_len       => 2,
                  'ref'         => 'const',
                  rows          => 512,
                  possible_keys => 'idx_fk_original_language_id',
                  partitions    => undef,
               },
               {  type          => 'Table',
                  table         => 'film',
                  possible_keys => 'idx_fk_original_language_id',
                  partitions    => undef,
               },
            ],
         },
      ],
   },
   'Index ref_or_null scan',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/rental_index_merge_intersect.sql") );
is_deeply(
   $t,
   {  type     => 'Filter with WHERE',
      id       => 1,
      rowid    => 0,
      children => [
         {  type     => 'Bookmark lookup',
            children => [
               {  type     => 'Index merge',
                  method   => 'intersect',
                  rows     => 1,
                  children => [
                     {  type => 'Index range scan',
                        key  => 'rental->idx_fk_inventory_id',
                        possible_keys =>
                           'idx_fk_inventory_id,idx_fk_customer_id',
                        partitions    => undef,
                        key_len => 3,
                        'ref'   => undef,
                        rows    => 1,
                     },
                     {  type => 'Index range scan',
                        key  => 'rental->idx_fk_customer_id',
                        possible_keys =>
                           'idx_fk_inventory_id,idx_fk_customer_id',
                        partitions    => undef,
                        key_len => 2,
                        'ref'   => undef,
                        rows    => 1,
                     },
                  ],
               },
               {  type          => 'Table',
                  table         => 'rental',
                  possible_keys => 'idx_fk_inventory_id,idx_fk_customer_id',
                  partitions    => undef,
               },
            ],
         },
      ],
   },
   'Index intersection merge',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/index_merge_three_keys.sql") );
is_deeply(
   $t,
   {  type     => 'Filter with WHERE',
      id       => 1,
      rowid    => 0,
      children => [
         {  type     => 'Index merge',
            method   => 'intersect',
            rows     => 2,
            children => [
               {  type          => 'Index range scan',
                  key           => 't1->key1',
                  possible_keys => 'key1,key2,key3',
                  partitions    => undef,
                  key_len       => 5,
                  'ref'         => undef,
                  rows          => 2,
               },
               {  type          => 'Index range scan',
                  key           => 't1->key2',
                  possible_keys => 'key1,key2,key3',
                  partitions    => undef,
                  key_len       => 5,
                  'ref'         => undef,
                  rows          => 2,
               },
               {  type          => 'Index range scan',
                  key           => 't1->key3',
                  possible_keys => 'key1,key2,key3',
                  partitions    => undef,
                  key_len       => 5,
                  'ref'         => undef,
                  rows          => 2,
               },
            ],
         },
      ],
   },
   'Index intersection merge with three keys and covering index',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/index_merge_union_intersect.sql") );
is_deeply(
   $t,
   {  type     => 'Filter with WHERE',
      id       => 1,
      rowid    => 0,
      children => [
         {  type     => 'Bookmark lookup',
            children => [
               {  type     => 'Index merge',
                  method   => 'union',
                  rows     => 154,
                  children => [
                     {  type     => 'Index merge',
                        method   => 'intersect',
                        rows     => 154,
                        children => [
                           {  type          => 'Index range scan',
                              key           => 't1->key1',
                              possible_keys => 'key1,key2,key3,key4',
                              partitions    => undef,
                              key_len       => 5,
                              'ref'         => undef,
                              rows          => 154,
                           },
                           {  type          => 'Index range scan',
                              key           => 't1->key2',
                              possible_keys => 'key1,key2,key3,key4',
                              partitions    => undef,
                              key_len       => 5,
                              'ref'         => undef,
                              rows          => 154,
                           },
                        ],
                     },
                     {  type     => 'Index merge',
                        method   => 'intersect',
                        rows     => 154,
                        children => [
                           {  type          => 'Index range scan',
                              key           => 't1->key3',
                              possible_keys => 'key1,key2,key3,key4',
                              partitions    => undef,
                              key_len       => 5,
                              'ref'         => undef,
                              rows          => 154,
                           },
                           {  type          => 'Index range scan',
                              key           => 't1->key4',
                              possible_keys => 'key1,key2,key3,key4',
                              partitions    => undef,
                              key_len       => 5,
                              'ref'         => undef,
                              rows          => 154,
                           },
                        ],
                     },
                  ],
               },
               {  type          => 'Table',
                  table         => 't1',
                  possible_keys => 'key1,key2,key3,key4',
                  partitions    => undef,
               },
            ],
         },
      ],
   },
   'Index merge union-intersection',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/index_merge_sort_union.sql") );
is_deeply(
   $t,
   {  type     => 'Filter with WHERE',
      id       => 1,
      rowid    => 0,
      children => [
         {  type     => 'Bookmark lookup',
            children => [
               {  type     => 'Index merge',
                  method   => 'sort_union',
                  rows     => 45,
                  children => [
                     {  type          => 'Index range scan',
                        key           => 't0->i1',
                        possible_keys => 'i1,i2',
                        partitions    => undef,
                        key_len       => 4,
                        'ref'         => undef,
                        rows          => 45,
                     },
                     {  type          => 'Index range scan',
                        key           => 't0->i2',
                        possible_keys => 'i1,i2',
                        partitions    => undef,
                        key_len       => 4,
                        'ref'         => undef,
                        rows          => 45,
                     },
                  ],
               },
               {  type          => 'Table',
                  table         => 't0',
                  possible_keys => 'i1,i2',
                  partitions    => undef,
               },
            ],
         },
      ],
   },
   'Index merge sort_union',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/optimized_away.sql") );
is_deeply(
   $t,
   {  type  => 'CONSTANT',
      id    => 1,
      rowid => 0,
   },
   'No tables used - constant',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/no_from.sql") );
is_deeply(
   $t,
   {  type  => 'DUAL',
      id    => 1,
      rowid => 0,
   },
   'No tables used - no FROM',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/filesort.sql") );
is_deeply(
   $t,
   {  type     => 'Filesort',
      id       => 1,
      rowid    => 0,
      children => [
         {  type     => 'Table scan',
            rows     => 951,
            children => [
               {  type          => 'Table',
                  table         => 'film',
                  possible_keys => undef,
                  partitions    => undef,
               },
            ],
         },
      ],
   },
   'Filesort',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/temporary_filesort.sql") );
is_deeply(
   $t,
   {  type     => 'Filesort',
      children => [
         {  type          => 'TEMPORARY',
            table         => 'temporary(film)',
            possible_keys => undef,
            partitions    => undef,
            children      => [
               {  type          => 'Index scan',
                  key           => 'film->PRIMARY',
                  possible_keys => undef,
                  partitions    => undef,
                  key_len       => 2,
                  'ref'         => undef,
                  rows          => 951,
                  rowid         => 0,
                  id            => 1,
               },
            ],
         },
      ],
   },
   'Filesort with temporary',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/filesort_on_subsequent_tbl.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type     => 'JOIN',
            children => [
               {  type     => 'Constant table access',
                  rows     => '1',
                  rowid    => 0,
                  id       => 1,
                  children => [
                     {  type          => 'Table',
                        table         => 'const_tbl',
                        possible_keys => undef,
                        partitions    => undef,
                     },
                  ],
               },
               {  type     => 'Filesort',
                  rowid    => 1,
                  id       => 1,
                  children => [
                     {  type     => 'Filter with WHERE',
                        children => [
                           {  type     => 'Table scan',
                              rows     => '10',
                              children => [
                                 {  type          => 'Table',
                                    table         => 't1',
                                    partitions    => undef,
                                    possible_keys => undef,
                                 },
                              ],
                           },
                        ],
                     },
                  ],
               },
            ],
         },
         {  type     => 'Filter with WHERE',
            rowid    => 2,
            id       => 1,
            children => [
               {  type     => 'Bookmark lookup',
                  children => [
                     {  type          => 'Index lookup',
                        key           => 't2->a',
                        key_len       => '5',
                        possible_keys => 'a',
                        ref           => 'test4.t1.a',
                        rows          => '11',
                        partitions    => undef,
                     },
                     {  type          => 'Table',
                        table         => 't2',
                        possible_keys => 'a',
                        partitions    => undef,
                     },
                  ],
               },
            ],
         },
      ],
   },
   'Filesort on first non-constant table',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/three_table_join_with_temp_filesort.sql") );
is_deeply(
   $t,
   {  type     => 'Filesort',
      children => [
         {  type          => 'TEMPORARY',
            partitions    => undef,
            possible_keys => undef,
            table         => 'temporary(actor,film_actor,film)',
            children      => [
               {  type     => 'JOIN',
                  children => [
                     {  type     => 'JOIN',
                        children => [
                           {  type          => 'Index scan',
                              key           => 'actor->PRIMARY',
                              possible_keys => 'PRIMARY',
                              key_len       => '2',
                              ref           => undef,
                              rows          => '200',
                              partitions    => undef,
                              rowid         => 0,
                              id            => 1,
                           },
                           {  type          => 'Index lookup',
                              key           => 'film_actor->PRIMARY',
                              key_len       => '2',
                              ref           => 'sakila.actor.actor_id',
                              rows          => '13',
                              partitions    => undef,
                              possible_keys => 'PRIMARY,idx_fk_film_id',
                              rowid         => 1,
                              id            => 1
                           }
                        ],
                     },
                     {  type          => 'Unique index lookup',
                        key           => 'film->PRIMARY',
                        possible_keys => 'PRIMARY',
                        key_len       => '2',
                        ref           => 'sakila.film_actor.film_id',
                        rows          => '1',
                        partitions    => undef,
                        rowid         => 2,
                        id            => 1,
                     }
                  ],
               }
            ],
         }
      ],
   },
   'Filesort with temporary',
);

eval {
   $t = $e->parse( load_file("t/pt-visual-explain/samples/too_many_unions.sql") );
};
like($EVAL_ERROR, qr/UNION has too many tables/, 'Too many unions');


$t = $e->parse( load_file("t/pt-visual-explain/samples/simple_union.sql") );
is_deeply(
   $t,
   {  type     => 'Table scan',
      rows     => undef,
      id       => 1,
      rowid    => 2,
      children => [
         {  type          => 'UNION',
            possible_keys => undef,
            partitions    => undef,
            table         => 'union(actor_1,actor_2)',
            children      => [
               {  type          => 'Index scan',
                  key           => 'actor_1->PRIMARY',
                  possible_keys => undef,
                  partitions    => undef,
                  key_len       => 2,
                  'ref'         => undef,
                  rows          => 200,
                  id            => 1,
                  rowid         => 0,
               },
               {  type          => 'Index scan',
                  key           => 'actor_2->PRIMARY',
                  possible_keys => undef,
                  partitions    => undef,
                  key_len       => 2,
                  'ref'         => undef,
                  rows          => 200,
                  id            => 2,
                  rowid         => 1,
               },
            ],
         },
      ],
   },
   'Simple union',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/derived_over_bookmark_lookup.sql") );
is_deeply(
   $t,
   {  type     => 'Table scan',
      rows     => 10,
      id       => 1,
      rowid    => 0,
      children => [
         {  type          => 'DERIVED',
            table         => 'derived(film_actor)',
            possible_keys => undef,
            partitions    => undef,
            children      => [
               {  type          => 'Bookmark lookup',
                  id            => 2,
                  rowid         => 1,
                  children      => [
                     {  type          => 'Index lookup',
                        key           => 'film_actor->idx_fk_film_id',
                        possible_keys => 'idx_fk_film_id',
                        partitions    => undef,
                        key_len       => 2,
                        'ref'         => undef,
                        rows          => 10,
                     },
                     {  type          => 'Table',
                        table         => 'film_actor',
                        possible_keys => 'idx_fk_film_id',
                        partitions    => undef,
                     },
                  ],
               },
            ],
         },
      ],
   },
   'Derived table over a bookmark lookup',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/simple_derived.sql") );
is_deeply(
   $t,
   {  type     => 'Table scan',
      rows     => 200,
      id       => 1,
      rowid    => 0,
      children => [
         {  type          => 'DERIVED',
            table         => 'derived(actor)',
            possible_keys => undef,
            partitions    => undef,
            children      => [
               {  type          => 'Index scan',
                  key           => 'actor->PRIMARY',
                  possible_keys => undef,
                  partitions    => undef,
                  key_len       => 2,
                  'ref'         => undef,
                  rows          => 200,
                  id            => 2,
                  rowid         => 1,
               },
            ],
         },
      ],
   },
   'Simple derived table',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/derived_over_join.sql") );
is_deeply(
   $t,
   {  type     => 'Table scan',
      rows     => 40000,
      id       => 1,
      rowid    => 0,
      children => [
         {  type          => 'DERIVED',
            table         => 'derived(actor_1,actor_2)',
            possible_keys => undef,
            partitions    => undef,
            children      => [
               {  type     => 'JOIN',
                  children => [
                     {  type          => 'Index scan',
                        key           => 'actor_1->PRIMARY',
                        possible_keys => undef,
                        partitions    => undef,
                        key_len       => 2,
                        'ref'         => undef,
                        rows          => 200,
                        id            => 2,
                        rowid         => 1,
                     },
                     {  type          => 'Index scan',
                        key           => 'actor_2->PRIMARY',
                        possible_keys => undef,
                        partitions    => undef,
                        key_len       => 2,
                        'ref'         => undef,
                        rows          => 200,
                        id            => 2,
                        rowid         => 2,
                     },
                  ],
               },
            ],
         },
      ],
   },
   'Simple derived table over a simple join',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/join_two_derived_tables_of_joins.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type     => 'Table scan',
            rows     => 40000,
            id       => 1,
            rowid    => 0,
            children => [
               {  type          => 'DERIVED',
                  table         => 'derived(actor_1,actor_2)',
                  possible_keys => undef,
                  partitions    => undef,
                  children      => [
                     {  type     => 'JOIN',
                        children => [
                           {  type          => 'Index scan',
                              key           => 'actor_1->PRIMARY',
                              possible_keys => undef,
                              partitions    => undef,
                              key_len       => 2,
                              'ref'         => undef,
                              rows          => 200,
                              id            => 2,
                              rowid         => 4,
                           },
                           {  type          => 'Index scan',
                              key           => 'actor_2->PRIMARY',
                              possible_keys => undef,
                              partitions    => undef,
                              key_len       => 2,
                              'ref'         => undef,
                              rows          => 200,
                              id            => 2,
                              rowid         => 5,
                           },
                        ],
                     },
                  ],
               },
            ],
         },
         {  type     => 'Filter with WHERE',
            id       => 1,
            rowid    => 1,
            children => [
               {  type     => 'Table scan',
                  rows     => 40000,
                  children => [
                     {  type          => 'DERIVED',
                        table         => 'derived(actor_3,actor_4)',
                        possible_keys => undef,
                        partitions    => undef,
                        children      => [
                           {  type     => 'JOIN',
                              children => [
                                 {  type          => 'Index scan',
                                    key           => 'actor_3->PRIMARY',
                                    possible_keys => undef,
                                    partitions    => undef,
                                    key_len       => 2,
                                    'ref'         => undef,
                                    rows          => 200,
                                    id            => 3,
                                    rowid         => 2,
                                 },
                                 {  type          => 'Index scan',
                                    key           => 'actor_4->PRIMARY',
                                    possible_keys => undef,
                                    partitions    => undef,
                                    key_len       => 2,
                                    'ref'         => undef,
                                    rows          => 200,
                                    id            => 3,
                                    rowid         => 3,
                                 },
                              ],
                           },
                        ],
                     },
                  ],
               },
            ],
         },
      ],
   },
   'Join two derived tables which each contain a join',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/union_of_derived_tables.sql") );
is_deeply(
   $t,
   {  type     => 'Table scan',
      rows     => undef,
      id       => 1,
      rowid    => 4,
      children => [
         {  type          => 'UNION',
            table         => 'union(derived(actor),derived(film))',
            possible_keys => undef,
            partitions    => undef,
            children      => [
               {  type     => 'Table scan',
                  id       => 1,
                  rowid    => 0,
                  rows     => 200,
                  children => [
                     {  type          => 'DERIVED',
                        table         => 'derived(actor)',
                        possible_keys => undef,
                        partitions    => undef,
                        children      => [
                           {  type          => 'Index scan',
                              key           => 'actor->PRIMARY',
                              possible_keys => undef,
                              partitions    => undef,
                              key_len       => 2,
                              'ref'         => undef,
                              rows          => 200,
                              id            => 2,
                              rowid         => 1,
                           },
                        ],
                     },
                  ],
               },
               {  type     => 'Table scan',
                  id       => 3,
                  rowid    => 2,
                  rows     => 1000,
                  children => [
                     {  type          => 'DERIVED',
                        table         => 'derived(film)',
                        possible_keys => undef,
                        partitions    => undef,
                        children      => [
                           {  type          => 'Index scan',
                              key           => 'film->idx_fk_language_id',
                              possible_keys => undef,
                              partitions    => undef,
                              key_len       => 1,
                              'ref'         => undef,
                              rows          => 951,
                              id            => 4,
                              rowid         => 3,
                           },
                        ],
                     },
                  ],
               },
            ],
         },
      ],
   },
   'Union over two derived tables',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/join_two_derived_tables_of_unions.sql") );
is_deeply(
   $t,
   {  type     => 'JOIN',
      children => [
         {  type     => 'Constant table access',
            id       => 1,
            rowid    => 0,
            rows     => 1,
            children => [
               {  type          => 'DERIVED',
                  table         => 'derived(union(actor_1,actor_2))',
                  possible_keys => undef,
                  partitions    => undef,
                  children      => [
                     {  type     => 'Table scan',
                        id       => 2,
                        rowid    => 7,
                        rows     => undef,
                        children => [
                           {  type          => 'UNION',
                              possible_keys => undef,
                              partitions    => undef,
                              table         => 'union(actor_1,actor_2)',
                              children      => [
                                 {  type          => 'Index scan',
                                    key           => 'actor_1->PRIMARY',
                                    possible_keys => undef,
                                    partitions    => undef,
                                    key_len       => 2,
                                    'ref'         => undef,
                                    rows          => 200,
                                    id            => 2,
                                    rowid         => 5,
                                 },
                                 {  type          => 'Index scan',
                                    key           => 'actor_2->PRIMARY',
                                    possible_keys => undef,
                                    partitions    => undef,
                                    key_len       => 2,
                                    'ref'         => undef,
                                    rows          => 200,
                                    id            => 3,
                                    rowid         => 6,
                                 },
                              ],
                           },
                        ],
                     }
                  ],
               },
            ],
         },
         {  type     => 'Constant table access',
            id       => 1,
            rowid    => 1,
            rows     => 1,
            children => [
               {  type          => 'DERIVED',
                  table         => 'derived(union(actor_3,actor_4))',
                  possible_keys => undef,
                  partitions    => undef,
                  children      => [
                     {  type     => 'Table scan',
                        id       => 4,
                        rowid    => 4,
                        rows     => undef,
                        children => [
                           {  type          => 'UNION',
                              possible_keys => undef,
                              partitions    => undef,
                              table         => 'union(actor_3,actor_4)',
                              children      => [
                                 {  type          => 'Index scan',
                                    key           => 'actor_3->PRIMARY',
                                    possible_keys => undef,
                                    partitions    => undef,
                                    key_len       => 2,
                                    'ref'         => undef,
                                    rows          => 200,
                                    id            => 4,
                                    rowid         => 2,
                                 },
                                 {  type          => 'Index scan',
                                    key           => 'actor_4->PRIMARY',
                                    possible_keys => undef,
                                    partitions    => undef,
                                    key_len       => 2,
                                    'ref'         => undef,
                                    rows          => 200,
                                    id            => 5,
                                    rowid         => 3,
                                 },
                              ],
                           },
                        ],
                     }
                  ],
               },
            ],
         },
      ],
   },
   'Join over two derived tables of unions',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/union_of_derived_unions.sql") );
is_deeply(
   $t,
   {  type     => 'Table scan',
      rows     => undef,
      id       => 1,
      rowid    => 8,
      children => [
         {  type => 'UNION',
            table =>
               'union(derived(union(actor_1,actor_2)),derived(union(actor_3,actor_4)))',
            possible_keys => undef,
            partitions    => undef,
            children      => [
               {  type     => 'Constant table access',
                  id       => 1,
                  rowid    => 0,
                  rows     => 1,
                  children => [
                     {  type          => 'DERIVED',
                        table         => 'derived(union(actor_1,actor_2))',
                        possible_keys => undef,
                        partitions    => undef,
                        children      => [
                           {  type     => 'Table scan',
                              id       => 2,
                              rowid    => 3,
                              rows     => undef,
                              children => [
                                 {  type          => 'UNION',
                                    possible_keys => undef,
                                    partitions    => undef,
                                    table         => 'union(actor_1,actor_2)',
                                    children      => [
                                       {  type          => 'Index scan',
                                          key           => 'actor_1->PRIMARY',
                                          possible_keys => undef,
                                          partitions    => undef,
                                          key_len       => 2,
                                          'ref'         => undef,
                                          rows          => 200,
                                          id            => 2,
                                          rowid         => 1,
                                       },
                                       {  type          => 'Index scan',
                                          key           => 'actor_2->PRIMARY',
                                          possible_keys => undef,
                                          partitions    => undef,
                                          key_len       => 2,
                                          'ref'         => undef,
                                          rows          => 200,
                                          id            => 3,
                                          rowid         => 2,
                                       },
                                    ],
                                 },
                              ],
                           }
                        ],
                     },
                  ],
               },
               {  type     => 'Table scan',
                  id       => 4,
                  rowid    => 4,
                  rows     => 400,
                  children => [
                     {  type          => 'DERIVED',
                        table         => 'derived(union(actor_3,actor_4))',
                        possible_keys => undef,
                        partitions    => undef,
                        children      => [
                           {  type     => 'Table scan',
                              rows     => undef,
                              id       => 5,
                              rowid    => 7,
                              children => [
                                 {  type          => 'UNION',
                                    possible_keys => undef,
                                    partitions    => undef,
                                    table         => 'union(actor_3,actor_4)',
                                    children      => [
                                       {  type          => 'Index scan',
                                          key           => 'actor_3->PRIMARY',
                                          possible_keys => undef,
                                          partitions    => undef,
                                          key_len       => 2,
                                          'ref'         => undef,
                                          rows          => 200,
                                          id            => 5,
                                          rowid         => 5,
                                       },
                                       {  type          => 'Index scan',
                                          key           => 'actor_4->PRIMARY',
                                          possible_keys => undef,
                                          partitions    => undef,
                                          key_len       => 2,
                                          'ref'         => undef,
                                          rows          => 200,
                                          id            => 6,
                                          rowid         => 6,
                                       },
                                    ],
                                 },
                              ]
                           },
                        ],
                     },
                  ],
               }
            ],
         },
      ],
   },
   'Union over two derived tables of unions',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/simple_subquery.sql") );
is_deeply(
   $t,
   {  type     => 'SUBQUERY',
      children => [
         {  type          => 'Index scan',
            rows          => 200,
            id            => 1,
            rowid         => 0,
            key_len       => 2,
            key           => 'actor->PRIMARY',
            possible_keys => undef,
            partitions    => undef,
            'ref'         => undef,
         },
         {  type          => 'Index scan',
            key           => 'film->idx_fk_language_id',
            possible_keys => undef,
            partitions    => undef,
            key_len       => 1,
            'ref'         => undef,
            rows          => 951,
            id            => 2,
            rowid         => 1,
         },
      ]
   },
   'Simple subquery',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/dependent_subquery.sql") );
is_deeply(
   $t,
   {  type     => 'DEPENDENT SUBQUERY',
      children => [
         {  type          => 'Index scan',
            rows          => 200,
            id            => 1,
            rowid         => 0,
            key_len       => 2,
            key           => 'actor->PRIMARY',
            possible_keys => undef,
            partitions    => undef,
            'ref'         => undef,
         },
         {  type     => 'Filter with WHERE',
            id       => 2,
            rowid    => 1,
            children => [
               {  type          => 'Index lookup',
                  key           => 'film_actor->PRIMARY',
                  possible_keys => 'PRIMARY',
                  partitions    => undef,
                  key_len       => 2,
                  'ref'         => 'actor.actor_id',
                  rows          => 13,
               },
            ],
         },
      ],
   },
   'Dependent subquery',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/uncacheable_subquery.sql") );
is_deeply(
   $t,
   {  type     => 'UNCACHEABLE SUBQUERY',
      children => [
         {  type          => 'Index scan',
            rows          => 200,
            id            => 1,
            rowid         => 0,
            key_len       => 2,
            key           => 'actor->PRIMARY',
            possible_keys => undef,
            partitions    => undef,
            'ref'         => undef,
         },
         {  type          => 'Index scan',
            key           => 'actor->PRIMARY',
            possible_keys => undef,
            partitions    => undef,
            key_len       => 2,
            'ref'         => undef,
            rows          => 200,
            id            => 2,
            rowid         => 1,
         },
      ],
   },
   'Dependent uncacheable subquery',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/join_in_subquery.sql") );
is_deeply(
   $t,
   {  type     => 'SUBQUERY',
      children => [
         {  type          => 'Index scan',
            rows          => 200,
            id            => 1,
            rowid         => 0,
            key_len       => 2,
            key           => 'actor->PRIMARY',
            possible_keys => undef,
            partitions    => undef,
            'ref'         => undef,
         },
         {  type     => 'JOIN',
            children => [
               {  type          => 'Index scan',
                  key           => 'film->idx_fk_language_id',
                  key_len       => 1,
                  possible_keys => 'PRIMARY',
                  partitions    => undef,
                  'ref'         => undef,
                  rows          => 951,
                  id            => 2,
                  rowid         => 1,
               },
               {  type          => 'Index lookup',
                  key           => 'film_actor->idx_fk_film_id',
                  possible_keys => 'idx_fk_film_id',
                  partitions    => undef,
                  key_len       => 2,
                  'ref'         => 'sakila.film.film_id',
                  rows          => 2,
                  id            => 2,
                  rowid         => 2,
               },
            ],
         },
      ],
   },
   'Join inside a subquery',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/unique_subquery_in_where_clause.sql") );
is_deeply(
   $t,
   {  type     => 'DEPENDENT SUBQUERY',
      children => [
         {  type     => 'Filter with WHERE',
            id       => 1,
            rowid    => 0,
            children => [
               {  type          => 'Index scan',
                  rows          => 5143,
                  key_len       => 2,
                  key           => 'film_actor->idx_fk_film_id',
                  possible_keys => undef,
                  partitions    => undef,
                  'ref'         => undef,
               },
            ],
         },
         {  type          => 'Unique subquery',
            rows          => 1,
            id            => 2,
            rowid         => 1,
            key_len       => 2,
            key           => 'actor->PRIMARY',
            possible_keys => 'PRIMARY',
            partitions    => undef,
            'ref'         => 'func',
         },
      ],
   },
   'Unique subquery',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/index_subquery_in_where_clause.sql") );
is_deeply(
   $t,
   {  type     => 'DEPENDENT SUBQUERY',
      children => [
         {  type     => 'Filter with WHERE',
            id       => 1,
            rowid    => 0,
            children => [
               {  type          => 'Index scan',
                  rows          => 200,
                  key_len       => 2,
                  key           => 'actor->PRIMARY',
                  possible_keys => undef,
                  partitions    => undef,
                  'ref'         => undef,
               },
            ],
         },
         {  type          => 'Index subquery',
            rows          => 13,
            id            => 2,
            rowid         => 1,
            key_len       => 2,
            key           => 'film_actor->PRIMARY',
            possible_keys => 'PRIMARY',
            partitions    => undef,
            'ref'         => 'func',
         },
      ],
   },
   'Index subquery',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/full_scan_on_null_key.sql") );
is_deeply(
   $t,
   {  type     => 'DEPENDENT SUBQUERY',
      children => [
         {  type     => 'Filter with WHERE',
            id       => 1,
            rowid    => 0,
            children => [
               {  type     => 'Table scan',
                  rows     => 4,
                  children => [
                     {  type          => 'Table',
                        table         => 't1',
                        possible_keys => undef,
                        partitions    => undef,
                     },
                  ],
               },
            ],
         },
         {  type     => 'JOIN',
            children => [
               {  type     => 'Filter with WHERE',
                  id       => 2,
                  rowid    => 1,
                  children => [
                     {  type          => 'Unique index lookup',
                        rows          => 1,
                        key_len       => 4,
                        key           => 't2->PRIMARY',
                        possible_keys => 'PRIMARY',
                        partitions    => undef,
                        'ref'         => 'func',
                        warning       => 'Full scan on NULL key',
                     },
                  ],
               },
               {  type     => 'Filter with WHERE',
                  id       => 2,
                  rowid    => 2,
                  children => [
                     {  type     => 'Bookmark lookup',
                        children => [
                           {  type          => 'Unique index lookup',
                              rows          => 1,
                              key_len       => 4,
                              key           => 't3->PRIMARY',
                              'ref'         => 'func',
                              warning       => 'Full scan on NULL key',
                              possible_keys => 'PRIMARY',
                              partitions    => undef,
                           },
                           {  type          => 'Table',
                              table         => 't3',
                              possible_keys => 'PRIMARY',
                              partitions    => undef,
                           },
                        ],
                     },
                  ],
               },
            ],
         },
      ],
   },
   'Subqueries that do a full scan on a NULL key',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/nested_derived_tables.sql") );
is_deeply(
   $t,
   {  type     => 'DEPENDENT SUBQUERY',
      children => [
         {  type     => 'Table scan',
            rows     => 1000,
            id       => 1,
            rowid    => 0,
            children => [
               {  type     => 'DERIVED',
                  table         => 'derived(derived(inner_der,inner_sub),mid_sub)',
                  possible_keys => undef,
                  partitions    => undef,
                  children => [
                     {  type     => 'DEPENDENT SUBQUERY',
                        children => [
                           {  type     => 'Table scan',
                              rows     => 1000,
                              id       => 3,
                              rowid    => 1,
                              children => [
                                 {  type     => 'DERIVED',
                                    table         => 'derived(inner_der,inner_sub)',
                                    possible_keys => undef,
                                    partitions    => undef,
                                    children => [
                                       {  type     => 'DEPENDENT SUBQUERY',
                                          children => [
                                             {  type     => 'Table scan',
                                                rows     => 951,
                                                id       => 5,
                                                rowid    => 2,
                                                children => [
                                                   {  type          => 'Table',
                                                      table         => 'inner_der',
                                                      possible_keys => undef,
                                                      partitions    => undef,
                                                   },
                                                ],
                                             },
                                             {  type     => 'Filter with WHERE',
                                                id       => 6,
                                                rowid    => 3,
                                                children => [
                                                   {  type          => 'Unique index lookup',
                                                      rows          => 1,
                                                      key_len       => 2,
                                                      key           => 'inner_sub->PRIMARY',
                                                      possible_keys => 'PRIMARY',
                                                      partitions    => undef,
                                                      'ref'         => 'inner_der.film_id',
                                                   },
                                                ],
                                             },
                                          ],
                                       },
                                    ],
                                 },
                              ],
                           },
                           {  type     => 'Filter with WHERE',
                              id       => 4,
                              rowid    => 4,
                              children => [
                                 {  type          => 'Unique index lookup',
                                    rows          => 1,
                                    key_len       => 2,
                                    key           => 'mid_sub->PRIMARY',
                                    possible_keys => 'PRIMARY',
                                    partitions    => undef,
                                    'ref'         => 'mid_der.film_id',
                                 },
                              ],
                           },
                        ],
                     },
                  ],
               },
            ],
         },
         {  type     => 'Filter with WHERE',
            id       => 2,
            rowid    => 5,
            children => [
               {  type          => 'Unique index lookup',
                  rows          => 1,
                  key_len       => 2,
                  key           => 'outer_sub->PRIMARY',
                  possible_keys => 'PRIMARY',
                  partitions    => undef,
                  'ref'         => 'outer_der.film_id',
               },
            ],
         },
      ],
   },
   'Nested derived tables and subqueries',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/adjacent_subqueries.sql") );
is_deeply(
   $t,
   {  type     => 'DEPENDENT SUBQUERY',
      children => [
         {  type     => 'SUBQUERY',
            children => [
               {  type    => 'Index scan',
                  key     => 'actor->PRIMARY',
                  key_len => 2,
                  rows    => 200,
                  'ref'   => undef,
                  partitions => undef,
                  possible_keys => undef,
                  id       => 1,
                  rowid    => 0,
               },
               {  type    => 'Index scan',
                  key     => 'f->idx_fk_language_id',
                  key_len => 1,
                  rows    => 951,
                  'ref'   => undef,
                  partitions => undef,
                  possible_keys => undef,
                  id       => 3,
                  rowid    => 1,
               },
            ],
         },
         {  type     => 'Filter with WHERE',
            id       => 2,
            rowid    => 2,
            children => [
               {  type          => 'Index lookup',
                  key           => 'film_actor->PRIMARY',
                  possible_keys => 'PRIMARY',
                  partitions => undef,
                  key_len       => 2,
                  'ref'         => 'actor.actor_id',
                  rows          => 13,
               },
            ],
         },
      ],
   },
   'Adjacent subqueries',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/complex_select_types.sql") );
is_deeply(
   $t,
   {  id       => '1',
      type     => 'Table scan',
      rows     => undef,
      rowid    => 7,
      children => [
         {  possible_keys => undef,
            table      => 'union(derived(actor),film_actor,derived(film,store),rental)',
            type       => 'UNION',
            partitions => undef,
            children   => [
               {  type     => 'DEPENDENT SUBQUERY',
                  children => [
                     {  id       => 1,
                        type     => 'Table scan',
                        rows     => '5',
                        rowid    => 0,
                        children => [
                           {  possible_keys => undef,
                              table         => 'derived(actor)',
                              type          => 'DERIVED',
                              partitions    => undef,
                              children      => [
                                 {  key_len       => '2',
                                    ref           => undef,
                                    rows          => '200',
                                    partitions    => undef,
                                    rowid         => 1,
                                    key           => 'actor->PRIMARY',
                                    possible_keys => undef,
                                    type          => 'Index scan',
                                    id            => 3
                                 }
                              ],
                           }
                        ],
                     },
                     {  key_len       => '2',
                        ref           => 'der_1.actor_id',
                        rows          => '13',
                        partitions    => undef,
                        rowid         => 2,
                        key           => 'film_actor->PRIMARY',
                        possible_keys => 'PRIMARY',
                        type          => 'Index lookup',
                        id            => 2
                     }
                  ],
               },
               {  type     => 'UNCACHEABLE SUBQUERY',
                  children => [
                     {  id       => 4,
                        type     => 'Table scan',
                        rows     => '5',
                        rowid    => 3,
                        children => [
                           {  possible_keys => undef,
                              table         => 'derived(film,store)',
                              type          => 'DERIVED',
                              partitions    => undef,
                              children      => [
                                 {  type     => 'SUBQUERY',
                                    children => [
                                       {  key_len       => '1',
                                          ref           => undef,
                                          rows          => '1022',
                                          partitions    => undef,
                                          rowid         => 4,
                                          key           => 'film->idx_fk_language_id',
                                          possible_keys => undef,
                                          type          => 'Index scan',
                                          id            => 6
                                       },
                                       {  key_len       => '1',
                                          ref           => undef,
                                          rows          => '2',
                                          partitions    => undef,
                                          rowid         => 5,
                                          key           => 'store->PRIMARY',
                                          possible_keys => undef,
                                          type          => 'Index scan',
                                          id            => 7
                                       }
                                    ],
                                 }
                              ],
                           }
                        ],
                     },
                     {  key_len       => '1',
                        ref           => undef,
                        rows          => '16305',
                        partitions    => undef,
                        rowid         => 6,
                        key           => 'rental->idx_fk_staff_id',
                        possible_keys => undef,
                        type          => 'Index scan',
                        id            => 5
                     }
                  ],
               }
            ],
         }
      ],
   },
   'Complex SELECT types combined',
);

$t = $e->parse( load_file("t/pt-visual-explain/samples/derived_without_table.sql") );
is_deeply(
   $t,
   {  id       => 1,
      type     => 'Constant table access',
      rows     => '1',
      rowid    => 0,
      children => [
         {  possible_keys => undef,
            table         => 'derived(<none>)',
            type          => 'DERIVED',
            partitions    => undef,
            children      => [
               {  id    => 2,
                  type  => 'DERIVED',
                  rowid => 1
               }
            ],
         }
      ],
   },
   'Recursive table name with anonymous derived table',
);

# #############################################################################
# Done.
# #############################################################################
exit;
