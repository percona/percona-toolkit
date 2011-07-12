#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 2;

use PerconaTest;
use PodParser;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $p = new PodParser();

$p->parse_from_file("$trunk/t/lib/samples/pod/pod_sample_mqa.txt");

is_deeply(
   $p->get_items(),
   {
      OPTIONS => {
         define => {
            desc => 'Define these check IDs.  If L<"--verbose"> is zero (i.e. not specified) then a terse definition is given.  If one then a fuller definition is given.  If two then the complete definition is given.',
            type => 'array',
         },
         'ignore-checks' => {
            desc => 'Ignore these L<"CHECKS">.',
            type => 'array',
         },
         verbose => {
            cumulative => 1,
            default    => '0',
            desc       => 'Print more information.',
         },
      },
   },
   'Parse pod_sample_mqa.txt'
);

# miu (mk-index-usage) has several MAGIC blocks.
$p->parse_from_file("$trunk/t/lib/samples/pod/pod_sample_miu.txt");
is_deeply(
   $p->get_magic(),
   {
      OPTIONS => {
         create_indexes => 'CREATE TABLE IF NOT EXISTS indexes (
  db           VARCHAR(64) NOT NULL,
  tbl          VARCHAR(64) NOT NULL,
  idx          VARCHAR(64) NOT NULL,
  cnt          BIGINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY  (db, tbl, idx)
)',
         create_queries => 'CREATE TABLE IF NOT EXISTS queries (
  query_id     BIGINT UNSIGNED NOT NULL,
  fingerprint  TEXT NOT NULL,
  sample       TEXT NOT NULL,
  PRIMARY KEY  (query_id)
)',
         view_index_has_alternates => 'SELECT CONCAT_WS(\'.\', db, tbl, idx) AS idx_chosen,
GROUP_CONCAT(DISTINCT alt_idx) AS alternatives,
GROUP_CONCAT(DISTINCT query_id) AS queries, SUM(cnt) AS cnt
FROM index_alternatives
GROUP BY db, tbl, idx
HAVING COUNT(*) > 1;',
         view_query_uses_several_indexes => 'SELECT iu.query_id, CONCAT_WS(\'.\', iu.db, iu.tbl, iu.idx) AS idx,
 variations, iu.cnt, iu.cnt / total_cnt * 100 AS pct
FROM index_usage AS iu
INNER JOIN (
 SELECT query_id, db, tbl, SUM(cnt) AS total_cnt,
 COUNT(*) AS variations
 FROM index_usage
 GROUP BY query_id, db, tbl
 HAVING COUNT(*) > 1
) AS qv USING(query_id, db, tbl);'
      }
   },
   "Parse pod_sample_miu.txt MAGIC"
);

# #############################################################################
# Done.
# #############################################################################
exit;
