#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use constant PTDEBUG => $ENV{PTDEBUG} || 0;
use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use Test::More;

use ExplainAnalyzer;
use QueryRewriter;
use QueryParser;
use DSNParser;
use Sandbox;
use PerconaTest;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master', {no_lc=>1});

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}

$dbh->do('use sakila');

my $qr  = new QueryRewriter();
my $qp  = new QueryParser();
my $exa = new ExplainAnalyzer(QueryRewriter => $qr, QueryParser => $qp);

# #############################################################################
# Tests for getting an EXPLAIN from a database.
# #############################################################################

is_deeply(
   $exa->explain_query(
      dbh   => $dbh,
      query => 'select * from actor where actor_id = 5',
   ),
   [
      { id            => 1,
        select_type   => 'SIMPLE',
        table         => 'actor',
        type          => 'const',
        possible_keys => 'PRIMARY',
        key           => 'PRIMARY',
        key_len       => 2,
        ref           => 'const',
        rows          => 1,
        Extra         => $sandbox_version eq '5.6' ? undef : '',
      },
   ],
   'Got a simple EXPLAIN result',
);

is_deeply(
   $exa->explain_query(
      dbh   => $dbh,
      query => 'delete from actor where actor_id = 5',
   ),
   [
      { id            => 1,
        select_type   => 'SIMPLE',
        table         => 'actor',
        type          => 'const',
        possible_keys => 'PRIMARY',
        key           => 'PRIMARY',
        key_len       => 2,
        ref           => 'const',
        rows          => 1,
        Extra         => $sandbox_version eq '5.6' ? undef : '',
      },
   ],
   'Got EXPLAIN result for a DELETE',
);

is(
   $exa->explain_query(
      dbh   => $dbh,
      query => 'insert into t values (1)',
   ),
   undef,
   "Doesn't EXPLAIN non-convertable non-SELECT"
);

# #############################################################################
# NOTE: EXPLAIN will vary between versions, so rely on the database as little as
# possible for tests.  Most things that need an EXPLAIN in the tests below
# should be using a hard-coded data structure.  Thus the following, intended to
# help prevent $dbh being used too much.
# #############################################################################
# XXX $dbh->disconnect;

# #############################################################################
# Tests for normalizing raw EXPLAIN into a format that's easier to work with.
# #############################################################################
is_deeply(
   $exa->normalize(
      [
         { id            => 1,
           select_type   => 'SIMPLE',
           table         => 'film_actor',
           type          => 'index_merge',
           possible_keys => 'PRIMARY,idx_fk_film_id',
           key           => 'PRIMARY,idx_fk_film_id',
           key_len       => '2,2',
           ref           => undef,
           rows          => 34,
           Extra         => 'Using union(PRIMARY,idx_fk_film_id); Using where',
         },
      ],
   ),
   [
      { id            => 1,
        select_type   => 'SIMPLE',
        table         => 'film_actor',
        type          => 'index_merge',
        possible_keys => [qw(PRIMARY idx_fk_film_id)],
        key           => [qw(PRIMARY idx_fk_film_id)],
        key_len       => [2,2],
        ref           => [qw()],
        rows          => 34,
        Extra         => {
           'Using union' => [qw(PRIMARY idx_fk_film_id)],
           'Using where' => 1,
        },
      },
   ],
   'Normalizes an EXPLAIN',
);

is_deeply(
   $exa->normalize(
      [
         { id            => 1,
           select_type   => 'PRIMARY',
           table         => undef,
           type          => undef,
           possible_keys => undef,
           key           => undef,
           key_len       => undef,
           ref           => undef,
           rows          => undef,
           Extra         => 'No tables used',
         },
         { id            => 1,
           select_type   => 'UNION',
           table         => 'a',
           type          => 'index',
           possible_keys => undef,
           key           => 'PRIMARY',
           key_len       => '2',
           ref           => undef,
           rows          => 200,
           Extra         => 'Using index',
         },
         { id            => undef,
           select_type   => 'UNION RESULT',
           table         => '<union1,2>',
           type          => 'ALL',
           possible_keys => undef,
           key           => undef,
           key_len       => undef,
           ref           => undef,
           rows          => undef,
           Extra         => '',
         },
      ],
   ),
   [
      { id            => 1,
        select_type   => 'PRIMARY',
        table         => undef,
        type          => undef,
        possible_keys => [],
        key           => [],
        key_len       => [],
        ref           => [],
        rows          => undef,
        Extra         => {
           'No tables used' => 1,
        },
      },
      { id            => 1,
        select_type   => 'UNION',
        table         => 'a',
        type          => 'index',
        possible_keys => [],
        key           => ['PRIMARY'],
        key_len       => [2],
        ref           => [],
        rows          => 200,
        Extra         => {
         'Using index' => 1,
        },
      },
      { id            => undef,
        select_type   => 'UNION RESULT',
        table         => '<union1,2>',
        type          => 'ALL',
        possible_keys => [],
        key           => [],
        key_len       => [],
        ref           => [],
        rows          => undef,
        Extra         => {},
      },
   ],
   'Normalizes a more complex EXPLAIN',
);

is_deeply(
   $exa->normalize(
      [
         { id            => 1,
           select_type   => 'SIMPLE',
           table         => 't1',
           type          => 'ALL',
           possible_keys => 'PRIMARY',
           key           => undef,
           key_len       => undef,
           ref           => undef,
           rows          => '4',
           # Extra         => 'Using where; Using temporary; Using filesort',
         },
      ],
   ),
   [
      {
         Extra          => {},  # is auto-vivified
         id             => 1,
         select_type    => 'SIMPLE',
         table          => 't1',
         type           => 'ALL',
         possible_keys  => ['PRIMARY'],
         key            => [],
         key_len        => [],
         ref            => [],
         rows           => '4',
      }
   ],
   "normalize() doesn't crash if EXPLAIN Extra is missing"
);

# #############################################################################
# Tests for trimming indexes out of possible_keys.
# #############################################################################
is_deeply(
   $exa->get_alternate_indexes(
      [qw(index1 index2)],
      [qw(index1 index2 index3 index4)],
   ),
   [qw(index3 index4)],
   'Normalizes alternate indexes',
);

# #############################################################################
# Tests for translating aliased names back to their real names.
# #############################################################################

# Putting it all together: given a query and an EXPLAIN, determine which indexes
# the query used.
is_deeply(
   $exa->get_index_usage(
      query => "select * from film_actor as fa inner join sakila.actor as a "
             . "on a.actor_id = fa.actor_id and a.last_name is not null "
             . "where a.actor_id = 5 or film_id = 5",
      db    => 'sakila',
      explain => $exa->normalize(
         [
            { id            => 1,
              select_type   => 'SIMPLE',
              table         => 'fa',
              type          => 'index_merge',
              possible_keys => 'PRIMARY,idx_fk_film_id',
              key           => 'PRIMARY,idx_fk_film_id',
              key_len       => '2,2',
              ref           => undef,
              rows          => 34,
              Extra         => 'Using union(PRIMARY,idx_fk_film_id); Using where',
            },
            { id            => 1,
              select_type   => 'SIMPLE',
              table         => 'a',
              type          => 'eq_ref',
              possible_keys => 'PRIMARY,idx_actor_last_name',
              key           => 'PRIMARY',
              key_len       => '2',
              ref           => 'sakila.fa.actor_id',
              rows          => 1,
              Extra         => 'Using where',
            },
         ],
      ),
   ),
   [  {  db  => 'sakila',
         tbl => 'film_actor',
         idx => [qw(PRIMARY idx_fk_film_id)],
         alt => [],
      },
      {  db  => 'sakila',
         tbl => 'actor',
         idx => [qw(PRIMARY)],
         alt => [qw(idx_actor_last_name)],
      },
   ],
   'Translate an EXPLAIN and a query into simplified index usage',
);

# This is kind of a pathological case.
is_deeply(
   $exa->get_index_usage(
      query   => "select 1 union select count(*) from actor a",
      db      => 'sakila',
      explain => $exa->normalize(
         [
            { id            => 1,
              select_type   => 'PRIMARY',
              table         => undef,
              type          => undef,
              possible_keys => undef,
              key           => undef,
              key_len       => undef,
              ref           => undef,
              rows          => undef,
              Extra         => 'No tables used',
            },
            { id            => 1,
              select_type   => 'UNION',
              table         => 'a',
              type          => 'index',
              possible_keys => undef,
              key           => 'PRIMARY',
              key_len       => '2',
              ref           => undef,
              rows          => 200,
              Extra         => 'Using index',
            },
            { id            => undef,
              select_type   => 'UNION RESULT',
              table         => '<union1,2>',
              type          => 'ALL',
              possible_keys => undef,
              key           => undef,
              key_len       => undef,
              ref           => undef,
              rows          => undef,
              Extra         => '',
            },
         ],
      ),
   ),
   [  {  db  => 'sakila',
         tbl => 'actor',
         idx => [qw(PRIMARY)],
         alt => [],
      },
   ],
   'Translate an EXPLAIN and a query for a harder case',
);

# Here's a query that uses a table but no indexes in it.
is_deeply(
   $exa->get_index_usage(
      query   => "select * from film_text",
      db      => 'sakila',
      explain => $exa->normalize(
         [
            { id            => 1,
              select_type   => 'SIMPLE',
              table         => 'film_text',
              type          => 'ALL',
              possible_keys => undef,
              key           => undef,
              key_len       => undef,
              ref           => undef,
              rows          => 1000,
              Extra         => '',
            },
         ],
      ),
   ),
   [  {  db  => 'sakila',
         tbl => 'film_text',
         idx => [],
         alt => [],
      },
   ],
   'Translate an EXPLAIN for a query that uses no indexes',
);

# #############################################################################
# Methods to save and retrieve index usage for a specific query and database.
# #############################################################################
is_deeply(
   $exa->get_usage_for('0xdeadbeef', 'sakila'),
   undef,
   'No usage recorded for 0xdeadbeef');

$exa->save_usage_for('0xdeadbeef', 'sakila',
   [  {  db  => 'sakila',
         tbl => 'actor',
         idx => [qw(PRIMARY)],
         alt => [],
      },
   ]);

is_deeply(
   $exa->get_usage_for('0xdeadbeef','sakila'),
   [  {  db  => 'sakila',
         tbl => 'actor',
         idx => [qw(PRIMARY)],
         alt => [],
      },
   ],
   'Got saved usage for 0xdeadbeef');

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
