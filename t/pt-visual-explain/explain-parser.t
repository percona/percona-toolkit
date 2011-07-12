#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 5;

use PerconaTest;
require "$trunk/bin/pt-visual-explain";

my $p = new ExplainParser;

is_deeply(
   $p->parse( load_file("t/pt-visual-explain/samples/full_scan_sakila_film.sql") ),
   [  {  id            => 1,
         select_type   => 'SIMPLE',
         table         => 'film',
         type          => 'ALL',
         possible_keys => undef,
         key           => undef,
         key_len       => undef,
         'ref'         => undef,
         rows          => 935,
         Extra         => undef,
      }
   ],
   'One line horizontal',
);

is_deeply(
   $p->parse( load_file("t/pt-visual-explain/samples/actor_join_film_ref.sql") ),
   [  {  id            => 1,
         select_type   => 'SIMPLE',
         table         => 'film',
         type          => 'ALL',
         possible_keys => 'PRIMARY',
         key           => undef,
         key_len       => undef,
         'ref'         => undef,
         rows          => 952,
         Extra         => undef,
      },
      {  id            => 1,
         select_type   => 'SIMPLE',
         table         => 'film_actor',
         type          => 'ref',
         possible_keys => 'idx_fk_film_id',
         key           => 'idx_fk_film_id',
         key_len       => 2,
         'ref'         => 'sakila.film.film_id',
         rows          => 2,
         Extra         => undef,
      },
   ],
   'Simple join',
);

is_deeply(
   $p->parse( load_file("t/pt-visual-explain/samples/rental_index_merge_intersect.sql") ),
   [  {  id            => 1,
         select_type   => 'SIMPLE',
         table         => 'rental',
         type          => 'index_merge',
         possible_keys => 'idx_fk_inventory_id,idx_fk_customer_id',
         key           => 'idx_fk_inventory_id,idx_fk_customer_id',
         key_len       => '3,2',
         'ref'         => undef,
         rows          => 1,
         Extra =>
            'Using intersect(idx_fk_inventory_id,idx_fk_customer_id); Using where',
      }
   ],
   'Vertical output',
);

is_deeply(
   $p->parse( load_file("t/pt-visual-explain/samples/index_merge_union_intersect.sql") ),
   [  {  id            => 1,
         select_type   => 'SIMPLE',
         table         => 't1',
         type          => 'index_merge',
         possible_keys => 'key1,key2,key3,key4',
         key           => 'key1,key2,key3,key4',
         key_len       => '5,5,5,5',
         'ref'         => undef,
         rows          => 154,
         Extra =>
            'Using union(intersect(key1,key2),intersect(key3,key4)); Using where',
      }
   ],
   'Tab-separated output',
);

is_deeply(
   $p->parse( load_file("t/pt-visual-explain/samples/simple_union.sql") ),
   [  {  id            => 1,
         select_type   => 'PRIMARY',
         table         => 'actor_1',
         type          => 'index',
         possible_keys => undef,
         key           => 'PRIMARY',
         key_len       => 2,
         'ref'         => undef,
         rows          => 200,
         Extra         => 'Using index',
      },
      {  id            => 2,
         select_type   => 'UNION',
         table         => 'actor_2',
         type          => 'index',
         possible_keys => undef,
         key           => 'PRIMARY',
         key_len       => 2,
         'ref'         => undef,
         rows          => 200,
         Extra         => 'Using index',
      },
      {  id            => undef,
         select_type   => 'UNION RESULT',
         table         => '<union1,2>',
         type          => 'ALL',
         possible_keys => undef,
         key           => undef,
         key_len       => undef,
         'ref'         => undef,
         rows          => undef,
         Extra         => undef,
      },
   ],
   'Tabular format with an empty cell',
);


# #############################################################################
# Done.
# #############################################################################
exit;
